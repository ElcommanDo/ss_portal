"""
JSON API used by the "Smart System Timesheet" Android app.

Every endpoint mirrors an existing web view in ``app/views.py``:
the same querysets, the same role checks and the same report formulas,
so numbers shown in the app match the numbers shown on the portal.
Original view names are referenced in each docstring.
"""
import calendar
import json
import os
import random
from collections import defaultdict
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from django.conf import settings
from django.contrib.auth import authenticate
from django.core.mail import EmailMultiAlternatives, send_mail
from django.db import transaction
from django.db.models import Case, CharField, Count, F, Max, Min, Prefetch, Q, Sum, Value, When
from django.shortcuts import get_object_or_404
from django.template.loader import render_to_string
from django.urls import reverse
from django.utils import timezone
from django.utils.html import strip_tags

from . import views as web
from .api_auth import (
    ApiError,
    api_view,
    clear_login_failures,
    decimal_or_error,
    int_or_none,
    login_is_locked,
    make_token,
    num,
    ok,
    paginate,
    read_json,
    register_login_failure,
)
from .models import (
    Assignement,
    CustomUser,
    EmployeeKPI,
    Project,
    ProjectCost,
    Team,
    Timesheet,
    TimesheetEntry,
    Vacation,
)
from .utils import get_priority_color, get_status_color

API_VERSION = 1

# --------------------------------------------------------------------------- #
# Role helpers (all based on the portal's own functions in views.py)
# --------------------------------------------------------------------------- #
def can_review(u):
    """Same rule as @user_passes_test(is_admin or is_manager or is_leader) in views.py."""
    return web.is_admin(u) or web.is_manager(u) or web.is_leader(u)


def can_process_vacations(u):
    """views.process_vacation"""
    return u.is_staff or u.role in ("leader", "ceo")


def sees_all_vacations(u):
    """views.vacation_requests"""
    return u.role in ("leader", "delivery-manager", "ceo") or u.is_superuser or u.is_staff


def capabilities(u):
    review = can_review(u)
    return {
        # dashboard.html switches between the employee and the admin layout on is_staff
        "staff_dashboard": bool(u.is_staff),
        "review_timesheets": review,
        "reports": review,
        "manage_users": review,
        "manage_teams": review,
        "delete_teams": web.is_admin(u),
        "projects": True,
        "add_project_cost": review,
        "assign_missions": review,
        "process_vacations": can_process_vacations(u),
        "all_vacations": sees_all_vacations(u),
    }


def leader_scope_users(u):
    """Users a leader manages (views.users / missions_list use team__team_lead=full_name)."""
    return CustomUser.objects.filter(team__team_lead=u.full_name)


def assignable_employees(u):
    if web.is_leader(u):
        qs = leader_scope_users(u)
    elif web.is_admin(u) or web.is_manager(u):
        qs = CustomUser.objects.all()
    else:
        qs = CustomUser.objects.none()
    return qs.filter(is_active=True).select_related("team").order_by("full_name")


def can_view_timesheet(u, ts):
    if ts.user_id == u.pk:
        return True
    if not can_review(u):
        return False
    if u.role == "leader":
        # views.timesheet scopes leaders to their own team
        return u.team_id is not None and ts.user.team_id == u.team_id
    return True


# --------------------------------------------------------------------------- #
# Serialisers
# --------------------------------------------------------------------------- #
ROLE_LABELS = dict(CustomUser.ROLE_CHOICES)


def fmt_dt(value):
    if value is None:
        return None
    if timezone.is_aware(value):
        value = timezone.localtime(value)
    return value.strftime("%Y-%m-%dT%H:%M:%S")


def fmt_d(value):
    return value.isoformat() if value else None


def fmt_t(value):
    if not value:
        return None
    if isinstance(value, str):
        return value[:5]
    return value.strftime("%H:%M")


def user_brief(u):
    if u is None:
        return None
    return {
        "id": u.pk,
        "username": u.username,
        "full_name": u.full_name or u.username,
        "role": u.role,
        "role_label": ROLE_LABELS.get(u.role, u.role).strip(),
        "team": u.team.title if u.team_id else None,
    }


def user_full(u):
    data = user_brief(u)
    data.update({
        "email": u.email,
        "is_active": u.is_active,
        "is_staff": u.is_staff,
        "is_superuser": u.is_superuser,
        "team_id": u.team_id,
        "date_joined": fmt_dt(u.date_joined),
    })
    return data


def project_brief(p):
    if p is None:
        return None
    return {"id": p.pk, "name": p.name}


def entry_json(e):
    return {
        "id": e.pk,
        "timesheet_id": e.time_sheet_id,
        "user": user_brief(e.user) if "user" in getattr(e, "_state").fields_cache else None,
        "project": project_brief(e.project),
        "task_type": e.task_type,
        "task_description": e.task_description,
        "hours": num(e.hours),
        "work_date": fmt_d(e.work_date),
        "status": e.status,
        "status_label": e.get_status_display(),
        "is_scheduled": e.is_scheduled,
        "time_start": fmt_t(e.time_start),
        "time_end": fmt_t(e.time_end),
        "onsite_abroad": e.onsite_abroad,
        "onsite_egypt": e.onsite_Egypt,
        "created_at": fmt_dt(e.created_at),
        "updated_at": fmt_dt(e.updated_at),
    }


def mission_json(m, now=None):
    now = now or timezone.now()
    status = (m.status or "").lower()
    return {
        "id": m.pk,
        "body": m.body,
        "priority": (m.priority or "").lower(),
        "status": status,
        "is_task": m.is_task,
        "project": project_brief(m.project),
        "deadline": fmt_dt(m.deadline),
        "is_overdue": bool(m.deadline and m.deadline < now and status != "completed"),
        "created_at": fmt_dt(m.created_at),
        "updated_at": fmt_dt(m.updated_at),
        "employee": user_brief(m.employee),
        "created_by": user_brief(m.created_by),
    }


def vacation_json(v):
    return {
        "id": v.pk,
        "user": user_brief(v.user),
        "date": fmt_d(v.date),
        "duration": v.duration,
        "reason": (v.reason or "").strip(),
        "status": v.status,
    }


# --------------------------------------------------------------------------- #
# Parsing helpers
# --------------------------------------------------------------------------- #
def parse_iso_date(value, field, required=True):
    if value in (None, ""):
        if required:
            raise ApiError(f"{field.replace('_', ' ').capitalize()} is required.", field=field)
        return None
    try:
        return datetime.strptime(str(value)[:10], "%Y-%m-%d").date()
    except ValueError:
        raise ApiError(f"Invalid date for {field}. Use YYYY-MM-DD.", field=field)


def parse_hhmm(value, field):
    if value in (None, ""):
        return None
    try:
        return datetime.strptime(str(value)[:5], "%H:%M").time()
    except ValueError:
        raise ApiError(f"Invalid time for {field}. Use HH:MM.", field=field)


def hours_between(start, end):
    """Hours between two times on the same day.
    Returned as float exactly like views.timesheet_create / timesheet_update, so the
    stored value (e.g. 2.3333 for 2h20m) is identical to an entry made on the portal."""
    delta = datetime.combine(date.today(), end) - datetime.combine(date.today(), start)
    return delta.total_seconds() / 3600.0


def latest_loggable_date():
    """Server TIME_ZONE is UTC while users are in Egypt / KSA (UTC+2/+3): right after
    midnight their 'today' is already tomorrow in UTC. Allow that one-day offset."""
    return timezone.localdate() + timedelta(days=1)


def allowed_entry_projects(u):
    """views.timesheet_create: active projects created by the user or public."""
    return Project.objects.filter(Q(is_active=True), Q(created_by=u) | Q(is_public=True)).distinct()


TASK_TYPES = [{"value": v, "label": l} for v, l in TimesheetEntry._meta.get_field("task_type").choices]
TASK_TYPE_VALUES = {t["value"] for t in TASK_TYPES}
MISSION_STATUSES = ["pending", "in_progress", "completed"]
MISSION_PRIORITIES = ["high", "medium", "low"]


def cleanup_empty_timesheet(ts_id):
    """Remove a daily Timesheet that has no entries left, so the
    'last timesheet' report does not count an empty day as activity."""
    if ts_id and not TimesheetEntry.objects.filter(time_sheet_id=ts_id).exists():
        Timesheet.objects.filter(pk=ts_id).delete()


def safe_send(callable_, *args, **kwargs):
    """Email failures must never break a mobile request: report them instead."""
    try:
        callable_(*args, **kwargs)
        return True
    except Exception as exc:  # SMTP / template / missing address
        print(f"[api] email not sent: {exc}")
        return False


def site_url(request, name, **kwargs):
    return request.build_absolute_uri(reverse(name, kwargs=kwargs or None))


# =========================================================================== #
# AUTH
# =========================================================================== #
@api_view(["POST"], auth=False)
def login(request):
    """views.login_request"""
    data = read_json(request)
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    if not username or not password:
        raise ApiError("Username and password are required.")
    if login_is_locked(request, username):
        raise ApiError("Too many failed attempts. Try again in 15 minutes.", 429)
    user = authenticate(request, username=username, password=password)
    if user is None:
        register_login_failure(request, username)
        raise ApiError("Username or Password is Incorrect.", 401)
    clear_login_failures(request, username)
    CustomUser.objects.filter(pk=user.pk).update(last_login=timezone.now())
    return ok({"token": make_token(user), "user": user_full(user), "capabilities": capabilities(user),
               "api_version": API_VERSION})


@api_view(["GET"])
def me(request):
    u = request.user
    return ok({"user": user_full(u), "capabilities": capabilities(u), "api_version": API_VERSION})


@api_view(["POST"])
def change_password(request):
    """views.change_password (+ validation, + a fresh token because old tokens die)."""
    data = read_json(request)
    u = request.user
    old_password = data.get("old_password") or ""
    new_password = data.get("new_password") or ""
    if not u.check_password(old_password):
        raise ApiError("The current password is not correct.", field="old_password")
    if len(new_password) < 6:
        raise ApiError("The new password must be at least 6 characters.", field="new_password")
    if new_password == old_password:
        raise ApiError("The new password must be different from the current one.", field="new_password")
    u.set_password(new_password)
    u.save()
    return ok({"token": make_token(u), "detail": "The Password Changed Successfully"})


# =========================================================================== #
# META / DASHBOARD
# =========================================================================== #
@api_view(["GET"])
def meta(request):
    u = request.user
    data = {
        "task_types": TASK_TYPES,
        "entry_projects": [project_brief(p) for p in allowed_entry_projects(u).order_by("name")],
        "mission_statuses": MISSION_STATUSES,
        "mission_priorities": MISSION_PRIORITIES,
        "roles": [{"value": v, "label": l.strip()} for v, l in CustomUser.ROLE_CHOICES],
        "today": fmt_d(timezone.now().date()),
        "server_time": fmt_dt(timezone.now()),
    }
    if can_review(u):
        if web.is_leader(u):
            users = leader_scope_users(u)
            teams = Team.objects.filter(team_lead=u.full_name)
        else:
            users = CustomUser.objects.all()
            teams = Team.objects.all()
        data["users"] = [user_brief(x) for x in users.select_related("team").order_by("full_name")]
        data["teams"] = [{"id": t.pk, "title": t.title} for t in teams.order_by("title")]
        data["projects"] = [project_brief(p) for p in Project.objects.order_by("name")]
        data["assignable_employees"] = [user_brief(x) for x in assignable_employees(u)]
    return ok(data)


def _wisdom():
    try:
        with open(os.path.join(settings.BASE_DIR, "config", "wisdom.json"), encoding="utf-8") as fh:
            items = json.load(fh)
        if items:
            return random.choice(items).get("quote")
    except Exception:
        pass
    return "إتقان العمل أمانة، وبالأمانة تُبنى الأمم."


@api_view(["GET"])
def dashboard(request):
    """views.timesheet_dashboard"""
    u = request.user
    today = timezone.now().date()
    start_of_week = today - timedelta(days=(today.weekday() + 1) % 7)  # Sunday
    end_of_week = start_of_week + timedelta(days=6)

    mine = TimesheetEntry.objects.filter(user=u)
    weekly_hours = mine.filter(work_date__gte=start_of_week, work_date__lte=end_of_week).aggregate(s=Sum("hours"))["s"] or 0
    today_hours = mine.filter(work_date=today, is_scheduled=False).aggregate(s=Sum("hours"))["s"] or 0
    month_hours = mine.filter(work_date__year=today.year, work_date__month=today.month, is_scheduled=False) \
                      .aggregate(s=Sum("hours"))["s"] or 0

    # Sun..Sat breakdown of the current week (logged work only)
    per_day = {row["work_date"]: row["h"] for row in
               mine.filter(work_date__gte=start_of_week, work_date__lte=end_of_week, is_scheduled=False)
                   .values("work_date").annotate(h=Sum("hours"))}
    week_days = []
    for i in range(7):
        d = start_of_week + timedelta(days=i)
        week_days.append({"date": fmt_d(d), "hours": num(per_day.get(d))})

    upcoming = mine.filter(is_scheduled=True, work_date__gte=today).select_related("project").order_by("work_date")[:5]
    recent = mine.filter(is_scheduled=False).select_related("project").order_by("-work_date", "-created_at")[:5]

    data = {
        "today": fmt_d(today),
        "week_start": fmt_d(start_of_week),
        "week_end": fmt_d(end_of_week),
        "weekly_hours": num(weekly_hours),
        "weekly_target": 40.0,
        "today_hours": num(today_hours),
        "month_hours": num(month_hours),
        "week_days": week_days,
        "daily_wisdom": _wisdom(),
        "open_missions": Assignement.objects.filter(employee=u).exclude(status__iexact="completed").count(),
        "pending_vacations": Vacation.objects.filter(user=u, status="pending").count(),
        "recent_entries": [entry_json(e) for e in recent],
        "upcoming_scheduled": [entry_json(e) for e in upcoming],
    }
    if u.is_staff:
        tz_start = timezone.make_aware(datetime.combine(today, time.min))
        tz_end = timezone.make_aware(datetime.combine(today, time.max))
        data["entries_today_count"] = TimesheetEntry.objects.filter(created_at__range=(tz_start, tz_end)).count()
        data["active_users_count"] = CustomUser.objects.filter(is_active=True).count()
        data["missions_created_open"] = Assignement.objects.filter(created_by=u).exclude(status__iexact="completed").count()
        if sees_all_vacations(u):
            data["vacations_waiting"] = Vacation.objects.filter(status="pending").count()
    return ok(data)


# =========================================================================== #
# MY TIMESHEETS / ENTRIES
# =========================================================================== #
SUMMARY_ANNOTATIONS = dict(
    total_hours=Sum("tasks__hours"),
    rejected_count=Count("tasks", filter=Q(tasks__status="REJECTED")),
    inprogress_count=Count("tasks", filter=Q(tasks__status="Inprogress")),
    approved_count=Count("tasks", filter=Q(tasks__status="APPROVED")),
    total_task_count=Count("tasks"),
)
SUMMARY_STATUS = Case(
    When(rejected_count__gt=0, then=Value("REJECTED")),
    When(inprogress_count__gt=0, then=Value("PENDING")),
    When(approved_count=F("total_task_count"), total_task_count__gt=0, then=Value("APPROVED")),
    default=Value("MIXED"),
    output_field=CharField(),
)


def _flag(request, name):
    return str(request.GET.get(name, "")).lower() in ("1", "true", "yes", "scheduled")


@api_view(["GET"])
def my_timesheets(request):
    """views.user_timesheets (logged or scheduled) — one row per day."""
    scheduled = _flag(request, "scheduled")
    qs = Timesheet.objects.filter(user=request.user, tasks__is_scheduled=scheduled).select_related("user")
    qs = qs.annotate(**SUMMARY_ANNOTATIONS).annotate(summary_status=SUMMARY_STATUS)

    filters = Q()
    work_date = parse_iso_date(request.GET.get("work_date"), "work_date", required=False)
    if work_date:
        filters &= Q(date=work_date)
    if request.GET.get("status"):
        filters &= Q(tasks__status=request.GET["status"])
    month = request.GET.get("month")  # YYYY-MM (app convenience filter)
    if month:
        try:
            m_start = datetime.strptime(month, "%Y-%m").date()
        except ValueError:
            raise ApiError("Invalid month. Use YYYY-MM.", field="month")
        filters &= Q(date__gte=m_start, date__lt=(m_start.replace(day=28) + timedelta(days=4)).replace(day=1))
    qs = qs.filter(filters).distinct().order_by("-date")

    def ser(ts):
        return {
            "id": ts.pk,
            "date": fmt_d(ts.date),
            "total_hours": num(ts.total_hours),
            "tasks_count": ts.total_task_count,
            "summary_status": ts.summary_status,
        }

    return ok(paginate(request, qs, ser))


@api_view(["GET"])
def timesheet_entries(request, pk):
    """views.my_timesheet_entries (owner) / views.timesheet_entries (reviewers)."""
    ts = get_object_or_404(Timesheet.objects.select_related("user", "user__team"), pk=pk)
    if not can_view_timesheet(request.user, ts):
        raise ApiError("You do not have permission to view this timesheet.", 403)
    qs = ts.tasks.select_related("project", "user", "user__team")
    if "scheduled" in request.GET:
        qs = qs.filter(is_scheduled=_flag(request, "scheduled"))
    if request.GET.get("project_pk"):
        qs = qs.filter(project__pk=int_or_none(request.GET["project_pk"]))
    qs = qs.order_by("time_start", "created_at")
    entries = list(qs)
    agg = qs.aggregate(total=Sum("hours"), abroad=Sum("hours", filter=Q(onsite_abroad=True)))
    return ok({
        "timesheet": {"id": ts.pk, "date": fmt_d(ts.date), "user": user_brief(ts.user)},
        "total_hours": num(agg["total"]),
        "abroad_hours": num(agg["abroad"]),
        "is_owner": ts.user_id == request.user.pk,
        "entries": [entry_json(e) for e in entries],
    })


@api_view(["GET", "POST"])
def entries(request):
    if request.method == "GET":
        # flat list of my entries (search / history)
        qs = TimesheetEntry.objects.filter(user=request.user).select_related("project")
        if "scheduled" in request.GET:
            qs = qs.filter(is_scheduled=_flag(request, "scheduled"))
        if request.GET.get("project_pk"):
            qs = qs.filter(project__pk=int_or_none(request.GET["project_pk"]))
        start = parse_iso_date(request.GET.get("start_date"), "start_date", required=False)
        end = parse_iso_date(request.GET.get("end_date"), "end_date", required=False)
        if start:
            qs = qs.filter(work_date__gte=start)
        if end:
            qs = qs.filter(work_date__lte=end)
        search = (request.GET.get("search") or "").strip()
        if search:
            qs = qs.filter(Q(task_description__icontains=search) | Q(project__name__icontains=search))
        return ok(paginate(request, qs.order_by("-work_date", "-created_at"), entry_json))
    return _create_entry(request)


def _create_entry(request):
    """views.timesheet_create — same fields & rules, with strict validation."""
    u = request.user
    data = read_json(request)
    is_scheduled = bool(data.get("is_scheduled"))
    task_date = parse_iso_date(data.get("work_date"), "work_date")
    today = timezone.localdate()

    project_id = int_or_none(data.get("project"))
    if not project_id:
        raise ApiError("Please select a project.", field="project")
    project = allowed_entry_projects(u).filter(pk=project_id).first()
    if project is None:
        raise ApiError("This project is not available for you.", field="project")

    task_type = data.get("task_type") or "Delivery"
    if task_type not in TASK_TYPE_VALUES:
        raise ApiError("Invalid task type.", field="task_type")
    description = (data.get("task_description") or "").strip()
    if not description:
        raise ApiError("Task description is required.", field="task_description")

    start = end = None
    hours = Decimal("0.00")
    if is_scheduled:
        if task_date <= today:
            raise ApiError("A scheduled task must be on a future date.", field="work_date")
    else:
        if task_date > latest_loggable_date():
            raise ApiError("You cannot log work on a future date. Use 'Schedule' instead.", field="work_date")
        start = parse_hhmm(data.get("start_time"), "start_time")
        end = parse_hhmm(data.get("end_time"), "end_time")
        if not start or not end:
            raise ApiError("Start time and end time are required.", field="start_time")
        if end <= start:
            raise ApiError("End time must be greater than start time.", field="end_time")
        hours = hours_between(start, end)

    location = data.get("location")
    with transaction.atomic():
        timesheet, _ = Timesheet.objects.get_or_create(user=u, date=task_date)
        obj = TimesheetEntry.objects.create(
            user=u,
            project=project,
            work_date=task_date,
            task_description=description,
            hours=hours,
            task_type=task_type,
            status="Inprogress",
            time_sheet=timesheet,
            is_scheduled=is_scheduled,
            time_start=start,
            time_end=end,
            onsite_abroad=(location == "abroad"),
            onsite_Egypt=(location == "egypt"),
        )
    obj.refresh_from_db()
    return ok({"detail": "Timesheet entry saved successfully!", "entry": entry_json(obj)}, status=201)


@api_view(["GET", "PUT", "PATCH", "DELETE"])
def entry_detail(request, pk):
    u = request.user
    if request.method == "GET":
        e = get_object_or_404(TimesheetEntry.objects.select_related("project", "user", "user__team", "time_sheet"), pk=pk)
        if e.user_id != u.pk and not (e.time_sheet and can_view_timesheet(u, e.time_sheet)):
            raise ApiError("You do not have permission to view this entry.", 403)
        return ok(entry_json(e))

    # only the owner can change an entry (views.timesheet_update / time_sheet_delete)
    e = get_object_or_404(TimesheetEntry.objects.select_related("project"), pk=pk, user=u)

    if request.method == "DELETE":
        ts_id = e.time_sheet_id
        with transaction.atomic():
            e.delete()
            cleanup_empty_timesheet(ts_id)
        return ok({"detail": "Time Sheet Entry Deleted Successfully"})

    # PUT / PATCH -> views.timesheet_update
    data = read_json(request)
    new_date = parse_iso_date(data.get("work_date", fmt_d(e.work_date)), "work_date")
    if new_date > latest_loggable_date():
        raise ApiError("You cannot select a future date.", field="work_date")

    if "task_description" in data:
        desc = (data.get("task_description") or "").strip()
        if not desc:
            raise ApiError("Task description is required.", field="task_description")
        e.task_description = desc
    if "task_type" in data and data["task_type"] != e.task_type:
        if data["task_type"] not in TASK_TYPE_VALUES:
            raise ApiError("Invalid task type.", field="task_type")
        e.task_type = data["task_type"]
    if data.get("project"):
        project = allowed_entry_projects(u).filter(pk=int_or_none(data["project"])).first()
        if project is None and int_or_none(data["project"]) != e.project_id:
            raise ApiError("This project is not available for you.", field="project")
        if project is not None:
            e.project = project
    if "location" in data:
        e.onsite_abroad = data["location"] == "abroad"
        e.onsite_Egypt = data["location"] == "egypt"

    start = parse_hhmm(data.get("start_time", fmt_t(e.time_start)), "start_time")
    end = parse_hhmm(data.get("end_time", fmt_t(e.time_end)), "end_time")
    if not start or not end:
        raise ApiError("Start time and end time are required.", field="start_time")
    if end <= start:
        raise ApiError("End time must be greater than start time.", field="end_time")

    old_ts_id = e.time_sheet_id
    with transaction.atomic():
        timesheet, _ = Timesheet.objects.get_or_create(user=e.user, date=new_date)
        e.time_start = start
        e.time_end = end
        e.hours = hours_between(start, end)
        e.work_date = new_date
        e.time_sheet = timesheet
        if data.get("mark_logged"):
            # a scheduled plan that has now been done -> it becomes logged work
            e.is_scheduled = False
        e.save()
        if old_ts_id != timesheet.pk:
            cleanup_empty_timesheet(old_ts_id)
    e.refresh_from_db()
    return ok({"detail": "Time Sheet Entry Updated Successfully.", "entry": entry_json(e)})


# =========================================================================== #
# KPI
# =========================================================================== #
@api_view(["GET"])
def my_kpi(request):
    """views.MyKPIView"""
    today = date.today()
    year = int_or_none(request.GET.get("year")) or today.year
    qm = int_or_none(request.GET.get("quarter_month")) or web.get_current_quarter_month()
    if qm not in (3, 6, 9, 12):
        raise ApiError("quarter_month must be 3, 6, 9 or 12.", field="quarter_month")
    kpis = EmployeeKPI.objects.filter(employee=request.user, year=year, quarter_month=qm) \
        .select_related("kpi_template", "kpi_template__category") \
        .order_by("kpi_template__category__name", "kpi_template__description")
    rows = []
    total = Decimal("0")
    for k in kpis:
        t = k.kpi_template
        total += k.score or 0
        rows.append({
            "id": k.pk,
            "category": t.category.name,
            "description": t.description,
            "way_of_measure": t.way_of_measure,
            "weight": num(t.weight),
            "grade": num(k.grade),
            "max_grade": num(t.max_grade),
            "score": num(k.score),
            "notes": k.notes,
        })
    return ok({
        "year": year,
        "quarter_month": qm,
        "quarter_label": web.get_quarter_label(qm),
        "total_score": num(total),
        "kpis": rows,
    })


# =========================================================================== #
# MISSIONS
# =========================================================================== #
@api_view(["GET", "POST"])
def missions(request):
    """views.missions_list"""
    u = request.user
    if request.method == "POST":
        return _create_mission(request)
    box = request.GET.get("box", "assigned")
    base = Assignement.objects.select_related("employee", "employee__team", "created_by", "created_by__team", "project")
    if box == "created":
        qs = base.filter(created_by=u)
        if request.GET.get("employee"):
            qs = qs.filter(employee_id=int_or_none(request.GET["employee"]))
    else:
        qs = base.filter(employee=u)
    st = (request.GET.get("status") or "").lower()
    if st == "open":
        qs = qs.exclude(status__iexact="completed")
    elif st:
        qs = qs.filter(status__iexact=st)
    now = timezone.now()
    return ok(paginate(request, qs.order_by("-deadline"), lambda m: mission_json(m, now)))


def _create_mission(request):
    """views.missions_list POST / views.assignement_create"""
    u = request.user
    if not can_review(u):
        raise ApiError("You do not have permission to assign missions.", 403)
    data = read_json(request)
    employee = assignable_employees(u).filter(pk=int_or_none(data.get("employee"))).first()
    if employee is None:
        raise ApiError("Please select an employee from your team.", field="employee")
    body = (data.get("body") or "").strip()
    if not body:
        raise ApiError("Mission details are required.", field="body")
    priority = (data.get("priority") or "medium").lower()
    if priority not in MISSION_PRIORITIES:
        raise ApiError("Invalid priority.", field="priority")
    raw_deadline = data.get("deadline") or ""
    try:
        deadline = datetime.strptime(raw_deadline[:16], "%Y-%m-%dT%H:%M")
    except ValueError:
        raise ApiError("Deadline is required (YYYY-MM-DDTHH:MM).", field="deadline")
    deadline = timezone.make_aware(deadline)  # same interpretation as the web datetime-local input
    project = None
    if data.get("project"):
        project = Project.objects.filter(pk=int_or_none(data["project"])).first()
        if project is None:
            raise ApiError("Project not found.", field="project")

    m = Assignement.objects.create(
        employee=employee, body=body, status="Pending", created_by=u, priority=priority,
        deadline=deadline, project=project, is_task=bool(data.get("is_task")),
    )

    email_sent = False
    if employee.email:
        html = render_to_string("mission_notification.html", {
            "employee": employee.full_name,
            "project": project.name if project else "General",
            "priority": m.priority,
            "deadline": m.deadline,
            "body": m.body,
            "accept_url": site_url(request, "accept_mission", pk=m.pk),
        })
        email_sent = safe_send(
            send_mail,
            f"🚀 New Mission Assigned: {project.name if project else 'General Task'}",
            "", settings.DEFAULT_FROM_EMAIL, [employee.email], html_message=html, fail_silently=False,
        )
    return ok({"detail": "The Assignment Created Successfully.", "mission": mission_json(m),
               "email_sent": email_sent}, status=201)


@api_view(["GET"])
def mission_detail(request, pk):
    m = get_object_or_404(Assignement.objects.select_related("employee", "created_by", "project"), pk=pk)
    if request.user.pk not in (m.employee_id, m.created_by_id) and not web.is_admin(request.user):
        raise ApiError("You do not have permission to view this mission.", 403)
    return ok(mission_json(m))


@api_view(["POST"])
def mission_status(request, pk):
    """views.mission_update — only the assigned employee updates the status."""
    m = get_object_or_404(Assignement.objects.select_related("employee", "created_by", "project"), pk=pk)
    if m.employee_id != request.user.pk:
        raise ApiError("You are not authorized to update this mission.", 403)
    new_status = (read_json(request).get("status") or "").lower()
    if new_status not in MISSION_STATUSES:
        raise ApiError("Status is required.", field="status")
    m.status = new_status
    m.save()

    ctx = {
        "creator_name": m.created_by.full_name or m.created_by.username,
        "employee_name": m.employee.full_name or m.employee.username,
        "project_name": m.project.name if m.project else "No Project",
        "priority": m.priority.upper(),
        "priority_color": get_priority_color(m.priority),
        "deadline": m.deadline.strftime("%d %B %Y, %I:%M %p"),
        "new_status": new_status.upper(),
        "status_color": get_status_color(new_status),
        "body": m.body,
        "updated_at": m.updated_at.strftime("%d %B %Y at %I:%M %p"),
        "mission_detail_url": site_url(request, "missions_list"),
    }
    recipients = [x for x in [m.created_by.email, "semad@smartsystemeg.com", "amustafa@smartsystemeg.com"] if x]

    def _send():
        html = render_to_string("mission_status_update.html", ctx)
        send_mail(
            subject=f"🚀 Mission Status Updated - {m.project.name if m.project else 'General Mission'}",
            message=strip_tags(html), from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=recipients, html_message=html, fail_silently=False,
        )

    email_sent = safe_send(_send)
    return ok({"detail": f"Mission status successfully updated to: {new_status}", "mission": mission_json(m),
               "email_sent": email_sent})


@api_view(["POST"])
def mission_accept(request, pk):
    """views.accept_mission — the employee confirms receipt; the creator is emailed."""
    m = get_object_or_404(Assignement.objects.select_related("employee", "created_by", "project"), pk=pk)
    if m.employee_id != request.user.pk:
        raise ApiError("Only the assigned employee can accept this mission.", 403)
    creator = m.created_by
    message = (
        f"Hello {creator.username},\n\n"
        f"{m.employee.username} has clicked \"ACCEPT MISSION\" and confirmed they received and understood the task.\n\n"
        f"Mission details:\n"
        f"• Project: {m.project.name if m.project else 'General Task'}\n"
        f"• Priority: {m.priority}\n"
        f"• Deadline: {m.deadline}\n\n"
        f"You can view the full mission here:\n{site_url(request, 'missions_list')}\n\n"
        f"Best regards,\nSmart Systems Command Center"
    )
    email_sent = bool(creator.email) and safe_send(
        send_mail, f"✅ Mission #{m.pk} ACCEPTED by {m.employee.username} - {m.employee.full_name}",
        message, settings.DEFAULT_FROM_EMAIL, [creator.email], fail_silently=False,
    )
    return ok({"detail": "Mission accepted. The creator has been notified." if email_sent
               else "Mission accepted.", "email_sent": email_sent})


@api_view(["POST"])
def mission_remind(request, pk):
    """views.send_mission_reminder"""
    m = get_object_or_404(Assignement.objects.select_related("employee"), pk=pk, created_by=request.user)
    if not m.employee.email:
        raise ApiError("This employee has no email address.")
    sent = safe_send(
        send_mail,
        f"🚨 URGENT: Mission Overdue - {m.body[:30]}...",
        f"Hello {m.employee.username},\n\nYour mission is currently OVERDUE.\n\nTask: {m.body}\n"
        f"Deadline: {m.deadline.strftime('%Y-%m-%d %H:%M')}\n\nPlease update the status immediately.",
        settings.DEFAULT_FROM_EMAIL, [m.employee.email],
    )
    if not sent:
        raise ApiError("Failed to send email. Check SMTP settings.", 502)
    return ok({"detail": f"Reminder sent to {m.employee.username}!"})


# =========================================================================== #
# VACATIONS
# =========================================================================== #
@api_view(["GET", "POST"])
def vacations(request):
    """views.vacation_requests / views.add_vacations"""
    u = request.user
    if request.method == "POST":
        data = read_json(request)
        v_date = parse_iso_date(data.get("date"), "date")
        duration = int_or_none(data.get("duration"))
        if not duration or duration < 1 or duration > 60:
            raise ApiError("Duration must be between 1 and 60 days.", field="duration")
        reason = (data.get("reason") or "").strip()
        if not reason:
            raise ApiError("Please write the reason.", field="reason")
        obj = Vacation.objects.create(user=u, date=v_date, reason=reason, duration=duration, status="pending")
        sent_to = "afarouk@smartsystemeg.com" if u.role in ("delivery-manager", "top-manager") else "semad@smartsystemeg.com"
        html = render_to_string("vacation_request_email.html", {
            "vacation": obj, "vacation_url": site_url(request, "vacation_requests")})
        email_sent = safe_send(send_mail, f"🚀 New Vacation Request: {u.username}", "",
                               settings.DEFAULT_FROM_EMAIL, [sent_to], html_message=html, fail_silently=False)
        return ok({"detail": "Vacation Request Sent", "vacation": vacation_json(obj), "email_sent": email_sent},
                  status=201)

    scope = request.GET.get("scope", "all" if sees_all_vacations(u) else "mine")
    if scope == "all" and sees_all_vacations(u):
        base = Vacation.objects.all()
    else:
        base = Vacation.objects.filter(user=u)
    base = base.select_related("user", "user__team").order_by("-date", "-id")
    qs = base
    search = (request.GET.get("search") or "").strip()
    if search:
        qs = qs.filter(Q(user__username__icontains=search) | Q(user__full_name__icontains=search) |
                       Q(reason__icontains=search))
    if request.GET.get("status"):
        qs = qs.filter(status=request.GET["status"])
    d = parse_iso_date(request.GET.get("date"), "date", required=False)
    if d:
        qs = qs.filter(date=d)
    today = date.today()
    data = paginate(request, qs, vacation_json)
    data["vacations_this_month"] = base.filter(date__year=today.year, date__month=today.month).count()
    data["pending_count"] = base.filter(status="pending").count()
    return ok(data)


@api_view(["POST"], permission=can_process_vacations)
def vacation_process(request, pk):
    """views.process_vacation"""
    data = read_json(request)
    action = (data.get("action") or "").lower()
    if action not in ("approved", "rejected"):
        raise ApiError("Action must be 'approved' or 'rejected'.", field="action")
    reject_reason = (data.get("reject_reason") or "").strip()
    v = get_object_or_404(Vacation.objects.select_related("user"), pk=pk)
    v.status = action
    v.save()
    email_sent = False
    if v.user.email:
        html = render_to_string("vacation_status_email.html", {
            "employee_name": v.user.full_name, "status": action, "date": v.date, "duration": v.duration,
            "reject_reason": reject_reason if action == "rejected" else None,
            "site_url": site_url(request, "vacation_requests"),
        })

        def _send():
            msg = EmailMultiAlternatives(f"Vacation Request Update: {action.capitalize()}", strip_tags(html),
                                         settings.DEFAULT_FROM_EMAIL, [v.user.email])
            msg.attach_alternative(html, "text/html")
            msg.send()

        email_sent = safe_send(_send)
    return ok({"detail": f"Vacation request for {v.user.username} has been {action}.",
               "vacation": vacation_json(v), "email_sent": email_sent})


@api_view(["POST"])
def vacation_cancel(request, pk):
    v = get_object_or_404(Vacation.objects.select_related("user"), pk=pk, user=request.user)
    if v.status != "pending":
        raise ApiError("Only pending requests can be cancelled.")
    v.status = "cancelled"
    v.save()
    return ok({"detail": "Vacation request cancelled.", "vacation": vacation_json(v)})


# =========================================================================== #
# REVIEW (managers / leaders)
# =========================================================================== #
@api_view(["GET"], permission=can_review)
def review_timesheets(request):
    """views.timesheet — identical filters, sums and leader scoping."""
    scheduled = _flag(request, "scheduled")
    project_pk = int_or_none(request.GET.get("project_pk"))
    user_pk = int_or_none(request.GET.get("user_pk"))
    team_pk = int_or_none(request.GET.get("team_pk"))
    work_date_str = request.GET.get("work_date")
    month_year_str = request.GET.get("month_year")
    week_start_date_str = request.GET.get("week_start_date")

    task_specific_filter = Q()
    if project_pk:
        task_specific_filter &= Q(tasks__project__pk=project_pk)
    task_specific_filter &= Q(tasks__is_scheduled=scheduled)

    main_filters = Q()
    if user_pk:
        main_filters &= Q(user__pk=user_pk)
    if team_pk:
        main_filters &= Q(user__team__pk=team_pk)
    if work_date_str:
        main_filters &= Q(date=parse_iso_date(work_date_str, "work_date"))
    elif month_year_str:
        try:
            start = datetime.strptime(month_year_str, "%Y-%m").date()
        except ValueError:
            raise ApiError("Invalid month. Use YYYY-MM.", field="month_year")
        end = (start.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)
        main_filters &= Q(date__gte=start, date__lte=end)
    elif week_start_date_str:
        start = parse_iso_date(week_start_date_str, "week_start_date")
        main_filters &= Q(date__gte=start, date__lte=start + timedelta(days=6))

    inner = Q(project__pk=project_pk) if project_pk else Q()
    inner &= Q(is_scheduled=scheduled)
    prefetch_tasks = Prefetch("tasks", queryset=TimesheetEntry.objects.filter(inner).select_related("project"))

    base = Timesheet.objects.all()
    if request.user.role == "leader":
        base = base.filter(user__team=request.user.team)
    base = base.filter(main_filters).filter(task_specific_filter)
    qs = base.select_related("user", "user__team").prefetch_related(prefetch_tasks).annotate(
        total_hours=Sum("tasks__hours", filter=task_specific_filter),
        onsite_abroad_hours=Sum("tasks__hours", filter=task_specific_filter & Q(tasks__onsite_abroad=True)),
        onsite_egypt_hours=Sum("tasks__hours", filter=task_specific_filter & Q(tasks__onsite_Egypt=True)),
    ).distinct().order_by("-date", "user__full_name")

    def ser(ts):
        tasks = list(ts.tasks.all())
        return {
            "id": ts.pk,
            "date": fmt_d(ts.date),
            "user": user_brief(ts.user),
            "total_hours": num(ts.total_hours),
            "onsite_abroad_hours": num(ts.onsite_abroad_hours),
            "onsite_egypt_hours": num(ts.onsite_egypt_hours),
            "tasks_count": len(tasks),
            "projects": sorted({t.project.name for t in tasks}),
            "task_types": sorted({t.task_type for t in tasks}),
        }

    result = paginate(request, qs, ser)
    agg = TimesheetEntry.objects.filter(time_sheet__in=base.values("id")).filter(inner).aggregate(h=Sum("hours"))
    result["sum_hours"] = num(agg["h"])
    return ok(result)


@api_view(["GET"], permission=can_review)
def users_list(request):
    """views.users"""
    u = request.user
    qs = leader_scope_users(u) if web.is_leader(u) else CustomUser.objects.all()
    search = (request.GET.get("search") or "").strip()
    if search:
        qs = qs.filter(Q(username__icontains=search) | Q(full_name__icontains=search))
    if request.GET.get("team_pk"):
        qs = qs.filter(team__pk=int_or_none(request.GET["team_pk"]))
    active = request.GET.get("active")
    if active in ("1", "0"):
        qs = qs.filter(is_active=(active == "1"))
    qs = qs.select_related("team").order_by("-date_joined")
    return ok(paginate(request, qs, user_full, default_size=30))


@api_view(["POST"], permission=can_review)
def user_toggle_active(request, pk):
    """views.toggle_user_status"""
    u = request.user
    scope = leader_scope_users(u) if web.is_leader(u) else CustomUser.objects.all()
    target = get_object_or_404(scope.select_related("team"), pk=pk)
    if target.pk == u.pk:
        raise ApiError("You cannot deactivate your own account.")
    if target.is_superuser and not u.is_superuser:
        raise ApiError("Only a superuser can change a superuser account.", 403)
    data = read_json(request)
    target.is_active = bool(data.get("active")) if "active" in data else not target.is_active
    target.save()
    return ok({"detail": f"Status for {target.full_name} is now {'Active' if target.is_active else 'Inactive'}.",
               "user": user_full(target)})


@api_view(["GET"], permission=can_review)
def teams_list(request):
    """views.teams"""
    u = request.user
    qs = Team.objects.filter(team_lead=u.full_name) if web.is_leader(u) else Team.objects.all()
    qs = qs.annotate(members=Count("employees", distinct=True),
                     active_members=Count("employees", filter=Q(employees__is_active=True), distinct=True)) \
        .order_by("title")
    return ok({"results": [{"id": t.pk, "title": t.title, "team_lead": t.team_lead, "members": t.members,
                            "active_members": t.active_members} for t in qs]})


@api_view(["GET"], permission=can_review)
def team_members(request, pk):
    """views.team_members"""
    u = request.user
    if web.is_leader(u):
        qs = leader_scope_users(u).filter(team__pk=pk)
    else:
        qs = CustomUser.objects.filter(team__pk=pk)
    return ok({"results": [user_full(x) for x in qs.select_related("team").order_by("full_name")]})


@api_view(["GET", "POST"])
def projects(request):
    """views.projects / views.project_create"""
    u = request.user
    if request.method == "POST":
        data = read_json(request)
        name = (data.get("name") or "").strip()
        if not name:
            raise ApiError("Project name is required.", field="name")
        if Project.objects.filter(name=name).exists():  # Project.name is unique=True
            raise ApiError("This Project Already Exists.", field="name")
        p = Project.objects.create(name=name, description=(data.get("description") or "").strip(), created_by=u,
                                   is_active=bool(data.get("is_active", True)),
                                   is_public=bool(data.get("is_public", False)))
        return ok({"detail": "The Project Created Successfully.", "project": _project_json(p)}, status=201)

    qs = Project.objects.filter(Q(created_by=u) | Q(is_public=True)).distinct()
    search = (request.GET.get("search") or "").strip()
    if search:
        qs = qs.filter(name__icontains=search)
    qs = qs.select_related("created_by").annotate(
        logged_hours=Sum("entries__hours", filter=Q(entries__is_scheduled=False)),
        contributors=Count("entries__user", distinct=True),
    ).order_by("name")
    return ok(paginate(request, qs, _project_json, default_size=30))


def _project_json(p):
    return {
        "id": p.pk,
        "name": p.name,
        "description": p.description,
        "is_active": p.is_active,
        "is_public": p.is_public,
        "created_by": (p.created_by.full_name or p.created_by.username) if p.created_by_id else None,
        "created_at": fmt_dt(p.created_at),
        "logged_hours": num(getattr(p, "logged_hours", 0)),
        "contributors": getattr(p, "contributors", 0),
    }


@api_view(["POST"], permission=can_review)
def project_add_cost(request, pk):
    """views.add_project_cost"""
    project = get_object_or_404(Project, pk=pk)
    data = read_json(request)
    employee = CustomUser.objects.filter(pk=int_or_none(data.get("employee"))).first()
    if employee is None:
        raise ApiError("Please select an employee.", field="employee")
    amount = decimal_or_error(data.get("amount"), "amount")
    if amount <= 0:
        raise ApiError("Amount must be greater than zero.", field="amount")
    currency = (data.get("currency") or "EGP").strip().upper()[:5]
    cost_type = (data.get("cost_type") or "").strip()[:60]
    if not cost_type:
        raise ApiError("Cost type is required.", field="cost_type")
    obj = ProjectCost.objects.create(user=employee, project=project, amount=amount.quantize(Decimal("0.01")),
                                     notes=(data.get("notes") or "").strip(), currency=currency, cost_type=cost_type)
    return ok({"detail": "The Cost Added Successfully.", "id": obj.pk}, status=201)


# =========================================================================== #
# REPORTS  (reports.html hub: admin / managers / leaders)
# =========================================================================== #
def _overtime_after_5pm(rows):
    """views.get_post_5pm_overtime on value rows."""
    cutoff = time(17, 0)
    ot = 0.0
    for r in rows:
        ts, te = r["time_start"], r["time_end"]
        if ts and te and te > cutoff:
            start = max(ts, cutoff)
            dummy = datetime.today()
            ot += max(0, (datetime.combine(dummy, te) - datetime.combine(dummy, start)).total_seconds() / 3600)
    return ot


def _man_days_queryset(request):
    qs = TimesheetEntry.objects.filter(is_scheduled=False).exclude(task_type="study")
    user_pk = request.GET.get("user_pk")
    project_pk = request.GET.get("project_pk")
    start_date = parse_iso_date(request.GET.get("start_date"), "start_date", required=False)
    end_date = parse_iso_date(request.GET.get("end_date"), "end_date", required=False)
    loc = request.GET.get("work_location")
    if user_pk:
        qs = qs.filter(user__pk=user_pk)
    if project_pk:
        qs = qs.filter(project__pk=project_pk)
    if start_date:
        qs = qs.filter(work_date__gte=start_date)
    if end_date:
        qs = qs.filter(work_date__lte=end_date)
    if loc == "abroad":
        qs = qs.filter(onsite_abroad=True)
    elif loc == "remote":
        qs = qs.filter(onsite_abroad=False)
    return qs


@api_view(["GET"], permission=can_review)
def report_man_days(request):
    """views.reports_daily_man_days — one row per employee per day."""
    STANDARD_HOURS = 8.0
    qs = _man_days_queryset(request)
    # Same aggregation as the portal (DB SUM per user/day). 3 queries instead of 2 per row.
    daily_stats = qs.values("work_date", "user__full_name", "user__username", "user__pk").annotate(
        total_daily_hours=Sum("hours"),
        egypt_hours=Sum("hours", filter=Q(onsite_Egypt=True)),
        abroad_hours=Sum("hours", filter=Q(onsite_abroad=True)),
    ).order_by("-work_date", "user__full_name")
    times = defaultdict(list)
    for r in qs.values("work_date", "user_id", "time_start", "time_end"):
        times[(r["work_date"], r["user_id"])].append(r)
    per_project = defaultdict(list)
    for r in qs.values("work_date", "user_id", "project__name").annotate(p_hours=Sum("hours")).order_by("project__name"):
        per_project[(r["work_date"], r["user_id"])].append({"name": r["project__name"], "hours": num(r["p_hours"], 4)})

    out = []
    totals = {"hours": 0.0, "ot": 0.0, "egypt": 0.0, "abroad": 0.0, "man_days": 0.0}
    for day in daily_stats:
        key = (day["work_date"], day["user__pk"])
        ot = float(_overtime_after_5pm(times[key]))
        logged = float(day["total_daily_hours"] or 0)
        egypt = float(day["egypt_hours"] or 0)
        abroad = float(day["abroad_hours"] or 0)
        work_for_manday = max(0, logged - ot)
        out.append({
            "work_date": fmt_d(day["work_date"]),
            "user_id": day["user__pk"],
            "user_full_name": day["user__full_name"] or day["user__username"],
            "total_hours": round(logged, 4),
            "overtime": round(ot, 4),
            "egypt_hours": round(egypt, 4),
            "abroad_hours": round(abroad, 4),
            "work_hours_for_manday": round(work_for_manday, 4),
            "man_day_display": f"{work_for_manday:g}/{STANDARD_HOURS:g}",
            "projects": per_project[key],
        })
        totals["hours"] += logged
        totals["ot"] += ot
        totals["egypt"] += egypt
        totals["abroad"] += abroad
        totals["man_days"] += work_for_manday / STANDARD_HOURS

    result = paginate(request, out, lambda x: x, default_size=50, max_size=500)
    result["totals"] = {k: round(v, 2) for k, v in totals.items()}
    result["standard_hours"] = STANDARD_HOURS
    return ok(result)


def _last_timesheet_rows(request):
    """views.reports_last_timesheet — exact same calculation."""
    today = timezone.now().date()
    WEEKLY_TARGET = 40.0
    week_mode = request.GET.get("week_mode", "current")
    custom_week_date = web.parse_date(request.GET.get("week_date"))
    if week_mode == "previous":
        ref = today - timedelta(days=7)
    elif week_mode == "custom" and custom_week_date:
        ref = custom_week_date
    else:
        ref = today
        week_mode = "current"
    week_start, week_end = web.get_week_range(ref)

    month_mode = request.GET.get("month_mode", "current")
    month_param = request.GET.get("month")
    if month_mode == "previous":
        last_month_end = today.replace(day=1) - timedelta(days=1)
        sel_y, sel_m = last_month_end.year, last_month_end.month
    elif month_mode == "custom" and month_param:
        try:
            sel_y, sel_m = map(int, month_param.split("-"))
            date(sel_y, sel_m, 1)
        except Exception:
            sel_y, sel_m, month_mode = today.year, today.month, "current"
    else:
        sel_y, sel_m, month_mode = today.year, today.month, "current"

    users = CustomUser.objects.filter(is_active=True).exclude(role__in=web.EXCLUDED_ROLES) \
        .exclude(username__in=["Aziz", "aziz"]).select_related("team").distinct().order_by("full_name")
    if request.GET.get("user_pk"):
        users = users.filter(pk=request.GET["user_pk"])
    user_ids = list(users.values_list("pk", flat=True))

    last_date_map = {r["user_id"]: r["last_date"] for r in
                     Timesheet.objects.filter(user_id__in=user_ids).values("user_id").annotate(last_date=Max("date"))}
    latest_ts_ids = {}
    for uid, last_date in last_date_map.items():
        ts = Timesheet.objects.filter(user_id=uid, date=last_date).order_by("-id").first()
        if ts:
            latest_ts_ids[uid] = ts.id
    timesheet_ids = list(latest_ts_ids.values())

    desc_map = {}
    if timesheet_ids:
        for e in TimesheetEntry.objects.filter(time_sheet_id__in=timesheet_ids, is_scheduled=False) \
                .exclude(web.STUDY_Q).order_by("time_sheet_id", "id"):
            desc_map.setdefault(e.time_sheet_id, e.task_description or "—")
        remaining = [t for t in timesheet_ids if t not in desc_map]
        if remaining:
            for e in TimesheetEntry.objects.filter(time_sheet_id__in=remaining, is_scheduled=False) \
                    .order_by("time_sheet_id", "id"):
                desc_map.setdefault(e.time_sheet_id, e.task_description or "—")

    weekly = defaultdict(lambda: {"total": 0.0, "vacation": 0.0})
    for e in TimesheetEntry.objects.filter(user_id__in=user_ids, is_scheduled=False, work_date__gte=week_start,
                                           work_date__lte=week_end).exclude(web.STUDY_Q) \
            .values("user_id", "work_date", "hours"):
        hrs = float(e["hours"] or 0)
        weekly[e["user_id"]]["total"] += hrs
        if e["work_date"].weekday() in (4, 5):
            weekly[e["user_id"]]["vacation"] += hrs

    monthly = {e["user_id"]: float(e["total"] or 0) for e in
               TimesheetEntry.objects.filter(user_id__in=user_ids, is_scheduled=False, work_date__year=sel_y,
                                             work_date__month=sel_m).exclude(web.STUDY_Q)
               .values("user_id").annotate(total=Sum("hours"))}

    _, dim = calendar.monthrange(sel_y, sel_m)
    working_days = sum(1 for d in range(1, dim + 1) if date(sel_y, sel_m, d).weekday() in (6, 0, 1, 2, 3))
    monthly_target = working_days * 8.0

    rows = []
    for u in users:
        last_date = last_date_map.get(u.pk)
        if not last_date:
            continue
        wt = weekly[u.pk]["total"]
        mt = monthly.get(u.pk, 0.0)
        rows.append({
            "user": user_brief(u),
            "work_date": last_date,
            "description": desc_map.get(latest_ts_ids.get(u.pk), "—"),
            "days_since_work": (today - last_date).days,
            "week_total": round(wt, 2),
            "week_vacation": round(weekly[u.pk]["vacation"], 2),
            "week_pct": round(wt / WEEKLY_TARGET * 100 if WEEKLY_TARGET else 0, 2),
            "month_total": round(mt, 2),
            "month_pct": round(mt / monthly_target * 100 if monthly_target else 0, 2),
        })
    sort = request.GET.get("sort", "days")
    if sort == "days":
        rows.sort(key=lambda x: x["days_since_work"] or 0, reverse=True)
    elif sort == "name":
        rows.sort(key=lambda x: x["user"]["full_name"].lower())
    elif sort == "date":
        rows.sort(key=lambda x: x["work_date"] or today, reverse=True)
    for r in rows:
        r["work_date"] = fmt_d(r["work_date"])
    meta = {
        "today": fmt_d(today),
        "week_mode": week_mode,
        "week_start": fmt_d(week_start),
        "week_end": fmt_d(week_end),
        "weekly_target": WEEKLY_TARGET,
        "month_mode": month_mode,
        "selected_month": f"{sel_y:04d}-{sel_m:02d}",
        "selected_month_label": date(sel_y, sel_m, 1).strftime("%B %Y"),
        "working_days": working_days,
        "monthly_target": monthly_target,
        "total_employees": len(rows),
    }
    return rows, meta


@api_view(["GET"], permission=can_review)
def report_last_timesheet(request):
    rows, meta = _last_timesheet_rows(request)
    result = paginate(request, rows, lambda x: x, default_size=100, max_size=500)
    result["meta"] = meta
    return ok(result)


def _monthly_rows(request):
    """views.reports_monthly_man_days — exact same calculation."""
    today = timezone.now().date()
    STANDARD_DAILY = 8.0
    user_pk = request.GET.get("user_pk")
    month_param = request.GET.get("month")
    year = int_or_none(request.GET.get("year")) or today.year
    is_full_year = month_param in (None, "", "all")
    month = None if is_full_year else int_or_none(month_param)
    if month is not None and not 1 <= month <= 12:
        raise ApiError("month must be 1-12 or 'all'.", field="month")

    users = CustomUser.objects.exclude(role__in=web.EXCLUDED_ROLES).exclude(username__in=web.EXCLUDED_USERNAMES) \
        .select_related("team").distinct().order_by("full_name")
    if user_pk:
        users = users.filter(pk=user_pk)
    user_ids = list(users.values_list("pk", flat=True))

    def working_days_of(y, m):
        _, dim = calendar.monthrange(y, m)
        return sum(1 for d in range(1, dim + 1) if datetime(y, m, d).weekday() in (6, 0, 1, 2, 3))

    rows, pcts = [], []
    total_main = total_extra = 0.0
    full_year_mode = is_full_year and bool(user_pk)
    if full_year_mode:
        selected = users.first()
        for m in range(1, 13):
            wd = working_days_of(year, m)
            target = wd * STANDARD_DAILY
            main = extra = 0.0
            for e in TimesheetEntry.objects.filter(user_id=user_pk, is_scheduled=False, work_date__year=year,
                                                   work_date__month=m).exclude(task_type="study") \
                    .values("work_date", "hours"):
                hrs = float(e["hours"] or 0)
                if e["work_date"].weekday() in (6, 0, 1, 2, 3):
                    main += hrs
                else:
                    extra += hrs
            pct = main / target * 100 if target > 0 else 0
            rows.append({"user": user_brief(selected) if selected else None, "month": m,
                         "month_name": calendar.month_name[m], "main_hours": round(main, 2),
                         "extra_hours": round(extra, 2), "total_hours": round(main + extra, 2),
                         "target": target, "percentage": round(pct, 2), "working_days": wd})
            total_main += main
            total_extra += extra
            pcts.append(pct)
    else:
        if not month:
            month = today.month
        wd = working_days_of(year, month)
        target = wd * STANDARD_DAILY
        stats = defaultdict(lambda: {"main": 0.0, "extra": 0.0})
        for e in TimesheetEntry.objects.filter(user_id__in=user_ids, is_scheduled=False, work_date__year=year,
                                               work_date__month=month).exclude(task_type="study") \
                .values("user_id", "work_date", "hours"):
            hrs = float(e["hours"] or 0)
            key = "main" if e["work_date"].weekday() in (6, 0, 1, 2, 3) else "extra"
            stats[e["user_id"]][key] += hrs
        for u in users:
            main, extra = stats[u.pk]["main"], stats[u.pk]["extra"]
            pct = main / target * 100 if target > 0 else 0
            rows.append({"user": user_brief(u), "month": month, "month_name": calendar.month_name[month],
                         "main_hours": round(main, 2), "extra_hours": round(extra, 2),
                         "total_hours": round(main + extra, 2), "target": target, "percentage": round(pct, 2),
                         "working_days": wd})
            total_main += main
            total_extra += extra
            pcts.append(pct)

    sort = request.GET.get("sort", "pct")
    if sort == "pct":
        rows.sort(key=lambda x: x["percentage"], reverse=True)
    elif sort == "name":
        rows.sort(key=lambda x: (x["user"] or {}).get("full_name", "").lower())
    elif sort == "main":
        rows.sort(key=lambda x: x["main_hours"], reverse=True)
    elif sort == "month" and is_full_year:
        rows.sort(key=lambda x: x["month"])

    meta = {
        "year": year,
        "selected_month": month_param if month_param else "all",
        "month_name": calendar.month_name[month] if month else "Full Year",
        "is_full_year": full_year_mode,
        "working_days": rows[0]["working_days"] if rows and not full_year_mode else None,
        "monthly_target": rows[0]["target"] if rows and not full_year_mode else None,
        "total_employees": len(rows),
        "avg_percentage": round(sum(pcts) / len(pcts), 2) if pcts else 0,
        "total_main": round(total_main, 2),
        "total_extra": round(total_extra, 2),
    }
    return rows, meta


@api_view(["GET"], permission=can_review)
def report_monthly_man_days(request):
    rows, meta = _monthly_rows(request)
    result = paginate(request, rows, lambda x: x, default_size=100, max_size=500)
    result["meta"] = meta
    return ok(result)


@api_view(["GET"], permission=can_review)
def report_project_costs(request):
    """views.reports_project_cost"""
    qs = ProjectCost.objects.select_related("project", "user").order_by("-pk")
    if request.GET.get("project_pk"):
        qs = qs.filter(project__pk=request.GET["project_pk"])
    if request.GET.get("user_pk"):
        qs = qs.filter(user__pk=request.GET["user_pk"])
    total_primary = qs.aggregate(t=Sum("amount", filter=Q(currency=web.PRIMARY_CURRENCY)))["t"] or Decimal("0")
    by_currency = {r["currency"]: num(r["t"]) for r in qs.values("currency").annotate(t=Sum("amount")).order_by("currency")}

    def ser(c):
        return {"id": c.pk, "project": project_brief(c.project), "user": user_brief(c.user),
                "amount": num(c.amount), "currency": c.currency, "cost_type": c.cost_type, "notes": c.notes}

    result = paginate(request, qs, ser, default_size=30)
    result["total_cost"] = num(total_primary)
    result["primary_currency"] = web.PRIMARY_CURRENCY
    result["totals_by_currency"] = by_currency
    return ok(result)


UTIL_EXCLUDE = Q(role__in=["top-manager", "project-manager", "admin", "ceo", "delivery-manager"]) | \
               Q(team__title__in=["PMO"])


def _util_dates(request, default_all=True):
    end_date = datetime.now().date()
    s, e = request.GET.get("start_date"), request.GET.get("end_date")
    if s and e:
        return parse_iso_date(s, "start_date"), parse_iso_date(e, "end_date")
    if not default_all:
        raise ApiError("start_date and end_date are required.")
    min_date = TimesheetEntry.objects.aggregate(m=Min("work_date"))["m"]
    return (min_date if min_date else end_date - timedelta(days=365)), end_date


@api_view(["GET"], permission=can_review)
def report_utilization(request):
    """views.utilization_report"""
    start_date, end_date = _util_dates(request)
    if start_date > end_date:
        raise ApiError("Start date must be before end date.", field="start_date")
    employees = CustomUser.objects.filter(is_active=True).exclude(UTIL_EXCLUDE).select_related("team") \
        .order_by("username")
    if request.GET.get("team_pk"):
        employees = employees.filter(team__pk=request.GET["team_pk"])
    rows = []
    for emp in employees:
        qs = TimesheetEntry.objects.filter(user=emp, work_date__range=[start_date, end_date]).exclude(status="DRAFT")
        total = qs.aggregate(t=Sum("hours"))["t"] or Decimal("0.00")
        workdays = web.get_workdays(start_date, end_date, emp)
        expected = workdays * 8
        util = float(total) / expected * 100 if expected > 0 else 0
        rows.append({"id": emp.pk, "username": emp.username, "full_name": emp.full_name or emp.username,
                     "team": emp.team.title if emp.team else "No Team", "total_hours": round(float(total), 2),
                     "expected_hours": expected, "utilization": round(util, 2), "entries_count": qs.count()})
    sort = request.GET.get("sort", "util")
    if sort == "util":
        rows.sort(key=lambda x: x["utilization"], reverse=True)
    elif sort == "name":
        rows.sort(key=lambda x: x["full_name"].lower())
    return ok({
        "start_date": fmt_d(start_date),
        "end_date": fmt_d(end_date),
        "total_employees": len(rows),
        "avg_utilization": round(sum(r["utilization"] for r in rows) / len(rows), 1) if rows else 0,
        "results": rows,
    })


@api_view(["GET"], permission=can_review)
def report_utilization_detail(request, employee_id):
    """views.employee_utilization_detail"""
    start_date, end_date = _util_dates(request)
    emp = get_object_or_404(CustomUser, pk=employee_id)
    qs = TimesheetEntry.objects.filter(user=emp, work_date__range=[start_date, end_date]).exclude(status="DRAFT") \
        .select_related("project").order_by("-work_date")
    entries_ = list(qs)
    total = sum((e.hours for e in entries_), Decimal("0"))
    workdays = web.get_workdays(start_date, end_date, emp)
    expected = workdays * 8
    util = float(total) / expected * 100 if expected > 0 else 0
    by_project, by_type = defaultdict(float), defaultdict(float)
    for e in entries_:
        by_project[e.project.name] += float(e.hours)
        by_type[e.task_type] += float(e.hours)
    return ok({
        "employee_name": emp.full_name or emp.username,
        "start_date": fmt_d(start_date),
        "end_date": fmt_d(end_date),
        "utilization": round(util, 2),
        "total_hours": round(float(total), 2),
        "expected_hours": expected,
        "workdays": workdays,
        "project_data": sorted([{"project": p, "hours": round(h, 2)} for p, h in by_project.items()],
                               key=lambda x: -x["hours"]),
        "task_data": sorted([{"type": t, "hours": round(h, 2)} for t, h in by_type.items()], key=lambda x: -x["hours"]),
        "entries": [{"work_date": fmt_d(e.work_date), "project": e.project.name,
                     "task_description": e.task_description, "hours": num(e.hours), "status": e.status,
                     "task_type": e.task_type} for e in entries_[:300]],
    })


@api_view(["GET"], permission=can_review)
def report_employee_activity(request):
    """views.reports_employee_activity"""
    period = request.GET.get("period", "month")
    user_pk = int_or_none(request.GET.get("user_pk"))
    if not user_pk:
        raise ApiError("Please select an employee.", field="user_pk")
    employee = get_object_or_404(CustomUser.objects.select_related("team"), pk=user_pk)
    start_date, end_date = web.get_date_range(period, request.GET.get("start_date"), request.GET.get("end_date"))
    qs = TimesheetEntry.objects.filter(user=employee)
    if request.GET.get("project_pk"):
        qs = qs.filter(project__pk=request.GET["project_pk"])
    qs = web.apply_date_filters(qs, start_date, end_date)
    m = qs.aggregate(total_hours=Sum("hours"), total_entries=Count("id"),
                     approved_count=Count(Case(When(status="APPROVED", then=1))),
                     distinct_projects=Count("project", distinct=True))
    total_entries = m["total_entries"] or 0
    approved_pct = (m["approved_count"] or 0) / total_entries * 100 if total_entries > 0 else 0
    by_type = defaultdict(float)
    for row in qs.values("task_type").annotate(h=Sum("hours")):
        by_type[row["task_type"]] += float(row["h"] or 0)

    def ser(e):
        return {"id": e.pk, "work_date": fmt_d(e.work_date), "project_name": e.project.name, "task_type": e.task_type,
                "hours": num(e.hours), "status": e.status, "is_scheduled": e.is_scheduled,
                "task_description": e.task_description}

    result = paginate(request, qs.select_related("project").order_by("-work_date", "-created_at"), ser,
                      default_size=50, max_size=500)
    result.update({
        "employee": user_brief(employee),
        "period": period,
        "start_date": fmt_d(start_date),
        "end_date": fmt_d(end_date),
        "total_logged_hours": num(m["total_hours"]),
        "total_entries": total_entries,
        "approved_percent": round(approved_pct, 2),
        "distinct_project_count": m["distinct_projects"] or 0,
        "task_type_hours": sorted([{"type": k, "hours": round(v, 2)} for k, v in by_type.items()],
                                  key=lambda x: -x["hours"]),
    })
    return ok(result)


# ---- PDF exports: the portal's own WeasyPrint views are reused unchanged ---- #
@api_view(["GET"], permission=can_review)
def pdf_man_days(request):
    return web.export_man_days_pdf(request)


@api_view(["GET"], permission=can_review)
def pdf_last_timesheet(request):
    return web.export_last_timesheet_pdf(request)


@api_view(["GET"], permission=can_review)
def pdf_monthly_man_days(request):
    return web.export_monthly_man_days_pdf(request)
