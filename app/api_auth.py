"""
Token authentication + helpers for the mobile JSON API (/api/v1/).

Design notes
------------
* No new models and no migrations: the token is a signed payload built with
  ``django.core.signing`` (HMAC with SECRET_KEY) that carries the user id and
  the user's *session auth hash*.  Changing the password changes that hash, so
  every token issued before a password change stops working automatically —
  the same rule Django applies to web sessions.
* Role rules are NOT re-invented here: they reuse ``is_admin``, ``is_manager``,
  ``is_leader`` ... from ``app.views`` so the app and the web portal always
  agree on who can do what.
"""
import json
from datetime import timedelta
from decimal import Decimal, InvalidOperation
from functools import wraps

from django.contrib.auth import get_user_model
from django.core import signing
from django.core.cache import cache
from django.core.paginator import Paginator
from django.http import Http404, JsonResponse
from django.utils.crypto import constant_time_compare
from django.views.decorators.csrf import csrf_exempt

TOKEN_SALT = "ss_portal.mobile-api.v1"
TOKEN_MAX_AGE = int(timedelta(days=30).total_seconds())

LOGIN_MAX_FAILURES = 8
LOGIN_LOCK_SECONDS = 15 * 60


class ApiError(Exception):
    """Raise inside an API view to return ``{"detail": message}`` with a status."""

    def __init__(self, message, status=400, field=None):
        super().__init__(message)
        self.message = message
        self.status = status
        self.field = field


# --------------------------------------------------------------------------- #
# Tokens
# --------------------------------------------------------------------------- #
def make_token(user):
    return signing.dumps(
        {"u": user.pk, "h": user.get_session_auth_hash()},
        salt=TOKEN_SALT,
        compress=True,
    )


def user_from_token(raw_token):
    try:
        data = signing.loads(raw_token, salt=TOKEN_SALT, max_age=TOKEN_MAX_AGE)
    except signing.SignatureExpired:
        raise ApiError("Your session has expired. Please sign in again.", 401)
    except signing.BadSignature:
        raise ApiError("Invalid session. Please sign in again.", 401)

    User = get_user_model()
    user = User.objects.select_related("team").filter(pk=data.get("u")).first()
    if user is None or not user.is_active:
        raise ApiError("This account is not active.", 401)
    if not constant_time_compare(user.get_session_auth_hash(), data.get("h", "")):
        # password was changed after the token was issued
        raise ApiError("Your password was changed. Please sign in again.", 401)
    return user


# --------------------------------------------------------------------------- #
# Login throttling (per username + per IP), uses the default cache
# --------------------------------------------------------------------------- #
def _throttle_keys(request, username):
    ip = request.META.get("HTTP_X_FORWARDED_FOR", "").split(",")[0].strip() or request.META.get("REMOTE_ADDR", "")
    return [f"api-login-fail:u:{(username or '').lower()}", f"api-login-fail:ip:{ip}"]


def login_is_locked(request, username):
    return any((cache.get(k) or 0) >= LOGIN_MAX_FAILURES for k in _throttle_keys(request, username))


def register_login_failure(request, username):
    for key in _throttle_keys(request, username):
        try:
            cache.add(key, 0, LOGIN_LOCK_SECONDS)
            cache.incr(key)
        except ValueError:
            cache.set(key, 1, LOGIN_LOCK_SECONDS)


def clear_login_failures(request, username):
    cache.delete_many(_throttle_keys(request, username))


# --------------------------------------------------------------------------- #
# View decorator
# --------------------------------------------------------------------------- #
def api_view(methods=("GET",), permission=None, auth=True):
    """
    * ``methods``    allowed HTTP methods.
    * ``permission`` callable(user) -> bool, checked after authentication.
    * ``auth``       set False for the login endpoint only.
    """
    methods = tuple(m.upper() for m in methods)

    def decorator(func):
        @csrf_exempt  # token in the Authorization header, no cookies -> CSRF not applicable
        @wraps(func)
        def wrapper(request, *args, **kwargs):
            if request.method not in methods:
                return JsonResponse({"detail": f"Method {request.method} not allowed."}, status=405)
            try:
                if auth:
                    header = request.headers.get("Authorization", "")
                    raw = header[6:].strip() if header.startswith("Token ") else ""
                    # some WSGI hosts (e.g. Apache mod_wsgi) drop "Authorization": accept a fallback header
                    raw = raw or request.headers.get("X-Auth-Token", "").strip()
                    if not raw:
                        raise ApiError("Authentication credentials were not provided.", 401)
                    request.user = user_from_token(raw)
                    if permission is not None and not permission(request.user):
                        raise ApiError("You do not have permission to perform this action.", 403)
                return func(request, *args, **kwargs)
            except ApiError as exc:
                body = {"detail": exc.message}
                if exc.field:
                    body["field"] = exc.field
                return JsonResponse(body, status=exc.status)
            except Http404:
                return JsonResponse({"detail": "Not found."}, status=404)

        return wrapper

    return decorator


# --------------------------------------------------------------------------- #
# Request / response helpers
# --------------------------------------------------------------------------- #
def read_json(request):
    if not request.body:
        return {}
    try:
        data = json.loads(request.body.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        raise ApiError("Request body must be valid JSON.")
    if not isinstance(data, dict):
        raise ApiError("Request body must be a JSON object.")
    return data


def ok(data=None, status=200):
    return JsonResponse(data if data is not None else {"ok": True}, status=status, safe=False,
                        json_dumps_params={"ensure_ascii": False})


def num(value, places=2):
    """Decimal/float/None -> float rounded for JSON."""
    if value is None:
        return 0.0
    return round(float(value), places)


def int_or_none(value):
    if value in (None, ""):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        raise ApiError(f"'{value}' is not a valid number.")


def decimal_or_error(value, field):
    try:
        result = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        raise ApiError(f"{field} must be a number.", field=field)
    if not result.is_finite():
        raise ApiError(f"{field} must be a number.", field=field)
    return result


def paginate(request, items, serializer, default_size=20, max_size=200):
    try:
        size = int(request.GET.get("page_size", default_size))
    except (TypeError, ValueError):
        size = default_size
    size = max(1, min(size, max_size))
    paginator = Paginator(items, size)
    page = paginator.get_page(request.GET.get("page"))
    return {
        "count": paginator.count,
        "page": page.number,
        "pages": paginator.num_pages,
        "page_size": size,
        "results": [serializer(obj) for obj in page.object_list],
    }
