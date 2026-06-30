from django.shortcuts import render, redirect, get_object_or_404
from django.urls import reverse
from django.http import FileResponse, Http404
from django.contrib.auth.decorators import login_required, user_passes_test
from django.contrib.auth import login, logout, authenticate
from django.contrib import messages
from . import models
from django.urls import reverse_lazy
from django.http import HttpResponse
from decimal import Decimal
from django.db.models import Q, Sum, Count, F, Max, Case, When, Value, CharField
from django.core.paginator import Paginator, EmptyPage, PageNotAnInteger
from datetime import datetime, timedelta, date, time
from dateutil.relativedelta import relativedelta
from django.db.models import DecimalField 
from .models import (CustomUser, TimesheetEntry, Project, ProjectCost, Team,
                      Timesheet, Assignement)
from django.contrib.auth import get_user_model
from django.conf import settings
import os
from django.db.models.functions import Coalesce
from django.contrib.auth.decorators import user_passes_test
import csv
from django.shortcuts import render, redirect
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.db import transaction 
import openpyxl 
import io 
from django.core.mail import send_mail
from django.conf import settings
from django.forms import modelformset_factory
PAGE_SIZE = 15
CustomUser = get_user_model()


# Create your views here.

def is_admin(user):
    return user.is_superuser or user.role == "admin"

def is_manager(user):
    return user.role in ["project-manager", "delivery-manager", "top-manager", "ceo"] 


def is_top_manager(user):
    return user.role in ["delivery-manager", "top-manager", "ceo"] 

def is_engineer(user):
    return user.role == "engineer" or user.role == "developer" 

def is_leader(user):
    return user.role == "leader"

def login_request(request):
    if request.user.is_authenticated:
        return redirect('home')
    if request.method == "POST":
        username = request.POST.get("username")
        password = request.POST.get("password")
        user = authenticate(request, username=username, password=password)
        if user:
            login(request, user)
            messages.success(request, f"Hello {user.username}!")
            return redirect("home")  # replace with your homepage url name
        else:
            messages.error(request, "Username or Password is Incorrect.")
    return render(request, 'login.html')


@login_required
def home(request):
    return render(request, 'dashboard.html', {
        "current_year": datetime.now().year,
         "current_month": datetime.now().month,

    })


@login_required
def timesheet_update(request, pk):
   
    if request.method =="POST":
        data = request.POST
        ts = TimesheetEntry.objects.get(pk=pk)
        ts.task_description = data.get("task_description", ts.task_description)
        ts.time_start = data.get("time_start", ts.time_start)
        ts.time_end = data.get("time_end", ts.time_end)
        ts.task_type = data.get("task_type", ts.task_type)
        if ts.project.name != data.get("project_name"):
            project = get_object_or_404(Project, name=data.get("project_name"))
            ts.project = project
        
        if ts.time_start and  ts.time_end:
            fmt = '%H:%M'
            t1 = datetime.strptime(ts.time_start, fmt)
            t2 = datetime.strptime(ts.time_end, fmt)

            # Calculate difference
            # Using absolute value to ensure it's positive regardless of order
            delta = abs(t2 - t1)
            
            # Convert total seconds to hours (float)
            hours = delta.total_seconds() / 3600.0
        else:
            hours = 0

        ts.hours = hours
        ts.save()
        next_url = request.POST.get('next')
        if hours <= 0:

            messages.error(request, "Hours spent must be greater than zero.")
            return redirect(next_url)
        messages.success(request, 'Time Sheet Entry Updated Successffully')
        return redirect(next_url)
        
@login_required
def time_sheet_delete(request, pk):
    if request.method == "POST":
        next_url = request.POST.get('next')
        ts = TimesheetEntry.objects.get(pk=pk)
        if request.user != ts.user:
            messages.warning(request, 'You Can not delete other user TimeSheet Entry')
            return redirect(next_url) 
        ts = TimesheetEntry.objects.get(pk=pk)
        ts.delete()
        messages.success(request, 'Time Sheet Entry Deleted Successffully')
        return redirect(next_url)
from django.utils import timezone
from django.utils.dateparse import parse_date

@login_required
def timesheet_create(request):
    user_projects = Q(created_by=request.user)
    public_projects = Q(is_public=True)
    projects = models.Project.objects.filter(Q(is_active=True), user_projects | public_projects).distinct()

    if request.method == 'POST':
        try:
            is_scheduled = request.POST.get("is_scheduled")
            # توحيد جلب التاريخ بناء على نوع العملية
            date_field = 'work_date_scheduled' if is_scheduled else 'work_date_logged'
            work_date_str = request.POST.get(date_field)

            if not work_date_str:
                messages.error(request, "Error: The Date of the Task is required.")
                return redirect('add_timesheet')

            # تحويل النص إلى Object تاريخ حقيقي لضمان الدقة
            task_date = parse_date(work_date_str)

            # إنشاء أو جلب الـ Timesheet بناء على تاريخ المهمة المختار (مش تاريخ النهاردة)
            timesheet, created = models.Timesheet.objects.get_or_create(
                user=request.user, 
                date=task_date
            )

            project_id = request.POST.get('project')
            task_description = request.POST.get('task_description')
            task_type = request.POST.get('task_type')

            # حساب الساعات
            hours = 0.00
            if not is_scheduled:
                start_time = request.POST.get('start_time')
                end_time = request.POST.get('end_time')
                if start_time and end_time:
                    fmt = '%H:%M'
                    t1 = datetime.strptime(start_time, fmt)
                    t2 = datetime.strptime(end_time, fmt)
                    delta = abs(t2 - t1)
                    hours = delta.total_seconds() / 3600.0
                
                if hours <= 0:
                    messages.error(request, "Hours spent must be greater than zero.")
                    return redirect('add_timesheet')

            project = get_object_or_404(models.Project, pk=project_id)

            # إنشاء السجل
            obj = models.TimesheetEntry.objects.create(
                user=request.user,
                project=project,
                work_date=task_date, # نستخدم الـ Object المحول
                task_description=task_description,
                hours=hours,
                task_type=task_type,
                status='Inprogress',
                time_sheet=timesheet,
                is_scheduled=bool(is_scheduled),
                time_start=request.POST.get('start_time') if not is_scheduled else None,
                time_end=request.POST.get('end_time') if not is_scheduled else None,
            )

            # معالجة الموقع
            location = request.POST.get("location")
            if location == "abroad":
                obj.onsite_abroad = True
            elif location == "egypt":
                obj.onsite_Egypt = True
            
            obj.save()
            messages.success(request, "Timesheet entry saved successfully!")
            return redirect('home')

        except Exception as e:
            messages.error(request, f"An error occurred: {e}")
            
    context = {'projects': projects, 'today': timezone.localdate()}
    return render(request, 'add_timesheet.html', context)

# @login_required
# def timesheet_update(request, pk):
#     if request.method == "POST":
#         data = request.POST
#         obj = get_object_or_404(models.TimesheetEntry, pk=pk)
#         obj.work_date = data.get("work_date")
#         obj.task_description = data.get("task_description")
#         obj.hours = data.get("hours")
#         obj.status = data.get("status")
#         obj.save()
#         messages.success(request, "The Time Sheet updated successfully...")
#         return redirect('home')

from django.db.models import Q # Add this import at the top

@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def users(request):
    # Get the search query from the URL parameters
    search_query = request.GET.get('search', '')

    if is_leader(request.user):
        user_list = models.CustomUser.objects.filter(team__team_lead=request.user.full_name)
        teams = Team.objects.filter(team_lead=request.user.full_name)
    else:
        user_list = models.CustomUser.objects.all()
        teams = models.Team.objects.all()

    # Apply Filter if search_query exists
    if search_query:
        user_list = user_list.filter(
            Q(username__icontains=search_query) | 
            Q(full_name__icontains=search_query)
        )

    user_list = user_list.order_by('-date_joined')

    paginator = Paginator(user_list, PAGE_SIZE)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    return render(request, 'users.html', {
        "role_choices": models.CustomUser.ROLE_CHOICES,
        "page_obj": page_obj,
        "users": page_obj.object_list,
        "teams": teams,
        "search_query": search_query # Pass it back to keep the input filled
    })


@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def team_members(request, pk):
    try:
        if is_leader(request.user):
            user_list = models.CustomUser.objects.filter(team__team_lead=request.user.full_name).order_by("-date_joined")
        else:
            user_list = models.CustomUser.objects.filter(team__pk=pk).order_by('username')

    except Exception as e:
        messages.warning(request, "You must choose team to display its memebers")
    paginator = Paginator(user_list, PAGE_SIZE)
    page_number = request.GET.get('page')
    
    page_obj = paginator.get_page(page_number)

    return render(request, 'team_members.html', {
        "page_obj": page_obj,
        "users": page_obj.object_list,
    })


@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def teams(request):
    if is_leader(request.user):
        team_list = models.Team.objects.filter(team_lead=request.user.full_name)
    else:
        team_list = models.Team.objects.all().order_by('title')
    
    # --- Pagination Logic ---
    paginator = Paginator(team_list, PAGE_SIZE)
    page_number = request.GET.get('page')
    
    # USE get_page for robust pagination handling
    page_obj = paginator.get_page(page_number)

    return render(request, 'teams.html', {
        "page_obj": page_obj,
        "teams": page_obj.object_list,
        "users": models.CustomUser.objects.values('full_name')
    })

@login_required
def projects(request):
    user_projects = Q(created_by=request.user)
    public_projects = Q(is_public=True)

    # Filter projects and order them
    project_list = models.Project.objects.filter(user_projects | public_projects).distinct().order_by('name')

    # --- Pagination Logic ---
    paginator = Paginator(project_list, PAGE_SIZE)
    page_number = request.GET.get('page')
    
    # USE get_page for robust pagination handling
    page_obj = paginator.get_page(page_number)
    
    return render(request, 'projects.html', {
        "page_obj": page_obj, 
        "projects": page_obj.object_list,
        "users": models.CustomUser.objects.values("pk", "full_name", "username")
    })



# @login_required
# def timesheet_dashboard(request):
#     user = request.user
#     context = {}
    
#     # 1. Determine Initial Queryset (Admin vs. Regular User)
#     if is_admin(user):
#         # Admin: Start with all entries
#         entries = models.TimesheetEntry.objects.select_related('user', 'project')
        
#         # Get filter parameters
#         status_filter = request.GET.get('status_filter', 'ALL')
#         search_term = request.GET.get('search_term', '').strip()
        
#         # --- Apply Filters ---
#         if status_filter != 'ALL':
#             entries = entries.filter(status=status_filter)

#         if search_term:
#             # Q object for filtering across user, project, and description
#             search_query = (
#                 Q(user__username__icontains=search_term) |
#                 Q(user__full_name__icontains=search_term) |
#                 Q(project__name__icontains=search_term) |
#                 Q(task_description__icontains=search_term)
#             )
#             entries = entries.filter(search_query)

#         # Admin context data
#         try:
#             context['users'] = models.CustomUser.objects.filter(is_active=True)
#             context['projects'] = models.Project.objects.filter(is_active=True)
#         except NameError:
#             context['users'] = []
#             context['projects'] = []
            
#         # Pass filter state back to the template
#         context['status_filter_selected'] = status_filter
#         context['search_term_entered'] = search_term

#         # Admin template name (or unified dashboard.html)
#         template = 'dashboard.html' 

#     else:
#         # Regular User: Filter by current user only
#         entries = models.TimesheetEntry.objects.filter(user=user).select_related('project')
        
#         # Calculate Weekly Hours for summary card
#         today = date.today()
#         start_of_week = today - timedelta(days=today.weekday())
#         end_of_week = start_of_week + timedelta(days=6)
        
#         weekly_hours_aggregation = entries.filter(
#             work_date__gte=start_of_week,
#             work_date__lte=end_of_week
#         ).aggregate(Sum('hours'))
        
#         weekly_hours = weekly_hours_aggregation.get('hours__sum', 0) or 0
#         context['weekly_hours'] = round(weekly_hours, 2)
#         template = 'dashboard.html'
    
    
#     # Final queryset ordering
#     entries = entries.order_by('-work_date')
    
#     # --- Apply Pagination to Final Queryset ---
#     paginator = Paginator(entries, PAGE_SIZE)
#     page_number = request.GET.get('page')
    
#     # USE get_page for robust pagination handling
#     page_obj = paginator.get_page(page_number)
    
#     # The template must now iterate over page_obj.object_list
#     context['timesheet_entries'] = page_obj.object_list
#     context['page_obj'] = page_obj 
#     today_start = datetime.combine(datetime.today(), time.min)

#     # Get the end of today (e.g., 2025-11-19 23:59:59.999999)
#     today_end = datetime.combine(datetime.today(), time.max)

#     # ... inside your view function ...

#     context['entries_today_count'] = str(models.TimesheetEntry.objects.filter(
#         created_at__gte=today_start, 
#         created_at__lte=today_end
#     ).count())
#     context['active_users_count'] = str(models.CustomUser.objects.filter(is_active=True).count())
#     return render(request, template, context)

from django.utils import timezone
from datetime import timedelta, datetime, time
import json
import os

@login_required
def timesheet_dashboard(request):
    user = request.user
    context = {
          "current_year": datetime.now().year,
         "current_month": datetime.now().month,

    }
    import random  

    try:

        json_path = os.path.join(settings.BASE_DIR, 'config', 'wisdom.json')
        
        with open(json_path, 'r', encoding='utf-8') as f:
            wisdoms_list = json.load(f)
            
            if wisdoms_list:
                random_wisdom = random.choice(wisdoms_list)
                context['daily_wisdom'] = random_wisdom['quote']
                
    except Exception as e:
        context['daily_wisdom'] = "إتقان العمل أمانة، وبالأمانة تُبنى الأمم."
        print(f"Error reading wisdom.json: {e}")
    today_dt = timezone.now()
    today_date = today_dt.date()

    # 1. Determine Initial Queryset (Admin vs. Regular User)
    if is_admin(user):
        entries = models.TimesheetEntry.objects.select_related('user', 'project')
        status_filter = request.GET.get('status_filter', 'ALL')
        search_term = request.GET.get('search_term', '').strip()
        
        if status_filter != 'ALL':
            entries = entries.filter(status=status_filter)

        if search_term:
            search_query = (
                Q(user__username__icontains=search_term) |
                Q(user__full_name__icontains=search_term) |
                Q(project__name__icontains=search_term) |
                Q(task_description__icontains=search_term)
            )
            entries = entries.filter(search_query)

        context['users'] = models.CustomUser.objects.filter(is_active=True)
        context['projects'] = models.Project.objects.filter(is_active=True)
        context['status_filter_selected'] = status_filter
        context['search_term_entered'] = search_term
        template = 'dashboard.html' 

    else:
        # Regular User: Filter by current user only
        entries = models.TimesheetEntry.objects.filter(user=user).select_related('project')
        
        # --- START OF WEEK (SUNDAY) CALCULATION ---
        # .weekday(): Mon=0, Tue=1, Wed=2, Thu=3, Fri=4, Sat=5, Sun=6
        # We want: Sun=0, Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6
        # Formula: (weekday + 1) % 7 calculates how many days since last Sunday
        days_since_sunday = (today_date.weekday() + 1) % 7
        start_of_week = today_date - timedelta(days=days_since_sunday)
        end_of_week = start_of_week + timedelta(days=6)
        
        weekly_hours_aggregation = entries.filter(
            work_date__gte=start_of_week,
            work_date__lte=end_of_week
        ).aggregate(Sum('hours'))
        
        weekly_hours = weekly_hours_aggregation.get('hours__sum', 0) or 0
        context['weekly_hours'] = round(weekly_hours, 2)
        template = 'dashboard.html'
    
    # Final queryset ordering
    entries = entries.order_by('-work_date')
    
    # Pagination
    paginator = Paginator(entries, PAGE_SIZE)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)
    
    context['timesheet_entries'] = page_obj.object_list
    context['page_obj'] = page_obj 

    # --- TODAY COUNTS (Using Timezone Aware Range) ---
    today_start = timezone.make_aware(datetime.combine(today_date, time.min))
    today_end = timezone.make_aware(datetime.combine(today_date, time.max))

    context['entries_today_count'] = models.TimesheetEntry.objects.filter(
        created_at__range=(today_start, today_end)
    ).count()
    
    context['active_users_count'] = models.CustomUser.objects.filter(is_active=True).count()
    context["current_year"] = "2026"
    context["month_year"] = "01"
    
    return render(request, template, context)

@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def user_edit(request, pk):
    user_to_edit = get_object_or_404(models.CustomUser, pk=pk)
    
    if request.method == 'POST':
        try:
            user_to_edit.username = request.POST.get('username', user_to_edit.username)
            user_to_edit.full_name = request.POST.get('full_name', user_to_edit.full_name)
            user_to_edit.role = request.POST.get('role', user_to_edit.role)
            team = models.Team.objects.get(pk=request.POST.get('team_pk'))
            user_to_edit.team = team
            
            new_password = request.POST.get('new_password')
            if new_password:
                user_to_edit.set_password(new_password)
                messages.warning(request, f"Password for {user_to_edit.full_name} was successfully changed.")
            
            if user_to_edit.role in ['admin', 'ceo', 'project-manager', 'leader']:
                user_to_edit.is_staff = True
            else:
                user_to_edit.is_staff = False
            
            user_to_edit.save()
            
            messages.success(request, f"User {user_to_edit.full_name}'s details were updated successfully.")
            return redirect('users')
            
        except Exception as e:
            messages.error(request, f"Error updating user: {e}")
            
    return redirect('users')


@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def toggle_user_status(request, pk):
    user_to_toggle = get_object_or_404(models.CustomUser, pk=pk)
    
    if request.method == 'POST':
        new_status_action = request.POST.get('new_status_action') 
        
        if new_status_action == 'Active':
            user_to_toggle.is_active = True
        elif new_status_action == 'Inactive':
            user_to_toggle.is_active = False
        
        user_to_toggle.save()
        
        messages.info(request, f"Status for {user_to_toggle.full_name} is now **{new_status_action}**.")
    
    return redirect('users')

@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def user_create(request):
    if request.method == "POST":
        data= request.POST
        if models.CustomUser.objects.filter(username=data.get("username")):
            messages.warning(request, "This Email Already Exist.")
            return redirect('users')
        user = models.CustomUser.objects.create(
            username = data.get("username"),
            full_name = data.get('full_name'),
            role = data.get('role'),
            email = data.get('email')
        ) 
        if data.get("team_pk"):
            user.team = models.Team.objects.get(pk = data.get("team_pk")) 
        user.set_password(data.get('generated_password'))
        if user.role not in ['admin','ceo', 'project-manager']:
            user.is_staff = False

        user.save()
        messages.success(request, 'The User Created Successfully.')
        return redirect('users')


@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def team_create(request):
    if request.method == "POST":
        data= request.POST
        if models.Team.objects.filter(title=data.get("title")):
            messages.warning(request, "This Team Already Exist.")
            return redirect('teams')
        team = models.Team.objects.create(
            title = data.get("title"),
            team_lead = data.get("team_lead"),
            
        ) 
        team.save()
        messages.success(request, 'The Team Created Successfully.')
        return redirect('teams')



@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def team_edit(request, pk):
    team_to_edit = get_object_or_404(models.Team, pk=pk)
    
    if request.method == 'POST':
        try:
            team_to_edit.title = request.POST.get('title', team_to_edit.title)
            team_to_edit.team_lead = request.POST.get('team_lead', team_to_edit.team_lead)
            
            team_to_edit.save()
            messages.success(request, f"team {team_to_edit.title}'s details were updated successfully.")
            return redirect('teams')
            
        except Exception as e:
            messages.error(request, f"Error updating team: {e}")
            
    return redirect('teams')


@user_passes_test(is_admin, login_url=reverse_lazy('home'))
def team_delete(request, pk):
    team_to_delete = get_object_or_404(models.Team, pk=pk)
    
    if request.method == 'POST':
        try:
            team_to_delete.delete() 
            messages.success(request, f"User {team_to_delete.title}'s details were Deleted successfully.")
            return redirect('teams')
            
        except Exception as e:
            messages.error(request, f"Error Deleting team: {e}")
            
    return redirect('teams')


@login_required
def logout_request(request):
    logout(request)
    messages.info(request, "User Logged Out Successfully.")
    return redirect("login") 



@login_required
def project_create(request):
    if request.method == "POST":
        data= request.POST
        user = request.user
        if models.Project.objects.filter(name=data.get("name"), created_by =user):
            messages.warning(request, "This Project Already Exist.")
            return redirect('projects')
        
        project = models.Project.objects.create(
            name = data.get("name"),
            description = data.get("description"),
            created_by = user
                        
        ) 
        if data.get("is_active") == "on":
            project.is_active=True
        else:
            project.is_active=False
        
        if data.get("is_public") == "on":
            project.is_public=True
        project.save()
        messages.success(request, 'The Project Created Successfully.')
        return redirect('projects')

@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def export_csv(request):
    response = HttpResponse(content_type='text/csv')
    filename = 'timesheet_export.csv'
    response['Content-Disposition'] = f'attachment; filename="{filename}"'

    writer = csv.writer(response)

    header = [
        'ID', 
        'User Full Name', 
        'User Username',
        'Work Date', 
        'Project Name', 
        'Hours', 
        'Task Description',
        'Task Type',
         
        'Status'
    ]
    writer.writerow(header)

    # 4. Fetch all data
    timesheet_entries = models.TimesheetEntry.objects.all().select_related('user', 'project')
    
    # 5. Write data rows
    for entry in timesheet_entries:
        # Access user full name safely (fallback to username)
        user_full_name = entry.user.full_name or entry.user.username
        
        row = [
            entry.pk,
            user_full_name,
            entry.user.username,
            entry.work_date.strftime('%Y-%m-%d'), # Format date for clean export
            entry.project.name,
            entry.hours,
            entry.task_description,
            entry.task_type,
            entry.get_status_display(), # Use the human-readable display value
        ]
        writer.writerow(row)

    return response


@login_required
def change_password(request):
    user = request.user
    if request.method == "POST":
        new_password = request.POST.get("new_password")
        old_password = request.POST.get("old_password")
        confirm_user = authenticate(request, username=user.username, password=old_password)
        if not confirm_user:
            messages.warning(request, "The Password is not correct")
            return redirect('home')            
        user.set_password(new_password)
        user.save()
        messages.success(request, "The Password Changed Successfully")
        return redirect('home')
    

# @user_passes_test(is_admin, login_url=reverse_lazy('home'))
# def timesheet(request):
    
#     queryset = TimesheetEntry.objects.select_related(
#         'user', 
#         'project',
#         'user__team' # Assuming CustomUser has a team field for efficiency
#     ).all()
    
#     # 2. Filter Logic (Q objects)
#     filters = Q()

#     # --- Employee Filter ---
#     user_pk = request.GET.get('user_pk')
#     if user_pk:
#         filters &= Q(user__pk=user_pk)

#     # --- Team Filter (Assuming CustomUser has a ForeignKey to Team) ---
#     team_pk = request.GET.get('team_pk')
#     if team_pk:
#         filters &= Q(user__team__pk=team_pk)

#     # --- Project Filter ---
#     project_pk = request.GET.get('project_pk')
#     if project_pk:
#         filters &= Q(project__pk=project_pk)

#     # --- Status Filter ---
#     status = request.GET.get('status')
#     if status:
#         filters &= Q(status=status)

#     # --- Date Filters ---
    
#     # Filter by Specific Day
#     work_date_str = request.GET.get('work_date')
#     if work_date_str:
#         try:
#             work_date = datetime.strptime(work_date_str, '%Y-%m-%d').date()
#             filters &= Q(work_date=work_date)
#         except ValueError:
#             # Optionally log error or show a user message
#             pass 
            
#     # Filter by Month/Year
#     month_year_str = request.GET.get('month_year')
#     if month_year_str:
#         try:
#             # The month input gives YYYY-MM
#             month_start = datetime.strptime(month_year_str, '%Y-%m').date()
#             month_end = month_start + relativedelta(months=1) - timedelta(days=1)
#             filters &= Q(work_date__gte=month_start, work_date__lte=month_end)
#         except ValueError:
#             pass

#     # Filter by Week (Uses week_start_date as the Monday of the desired week)
#     week_start_date_str = request.GET.get('week_start_date')
#     if week_start_date_str:
#         try:
#             # Assuming week starts on Monday
#             week_start = datetime.strptime(week_start_date_str, '%Y-%m-%d').date()
#             week_end = week_start + timedelta(days=6)
#             filters &= Q(work_date__gte=week_start, work_date__lte=week_end)
#         except ValueError:
#             pass

#     # Apply all gathered filters
#     queryset = queryset.filter(filters)
    
#     # 3. Pagination
#     paginator = Paginator(queryset, 20)  # Show 20 entries per page
#     page = request.GET.get('page', 1)

#     try:
#         page_obj = paginator.page(page)
#     except PageNotAnInteger:
#         page_obj = paginator.page(1)
#     except EmptyPage:
#         page_obj = paginator.page(paginator.num_pages)

#     # 4. Context Data
#     # Prepare data for filter dropdowns
#     status_choices = TimesheetEntry.STATUS_CHOICES
    
#     context = {
#         'page_obj': page_obj,
#         'all_users': CustomUser.objects.order_by('full_name').all(),
#         'all_teams': Team.objects.order_by('title').all(),
#         'all_projects': Project.objects.order_by('name').all(),
#         'status_choices': status_choices,
#         'current_params': request.GET.urlencode(), # Used to persist filters in pagination
#     }

#     return render(request, 'time_sheets.html', context)


# @user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
# def timesheet(request, scheduled=None):

#     if scheduled:
#         queryset = Timesheet.objects.select_related(
#             'user', 
#             'user__team'
#         ).filter(tasks__is_scheduled=True)
#     else:
#         queryset = Timesheet.objects.select_related(
#             'user', 
#             'user__team'
#         ).filter(tasks__is_scheduled=False)

#     if request.user.role == 'leader':
#         queryset = queryset.filter(user__team=request.user.team)
#     queryset = queryset.annotate(
#         total_hours=Sum('tasks__hours'),
#     )

#     filters = Q()

#     user_pk = request.GET.get('user_pk')
#     if user_pk:
#         filters &= Q(user__pk=user_pk)

#     team_pk = request.GET.get('team_pk')
#     if team_pk:
#         filters &= Q(user__team__pk=team_pk)

#     project_pk = request.GET.get('project_pk')
#     if project_pk:
#         filters &= Q(tasks__project__pk=project_pk)

#     status = request.GET.get('status')
#     if status:
#         filters &= Q(tasks__status=status)

#     work_date_str = request.GET.get('work_date')
#     if work_date_str:
#         try:
#             work_date = datetime.strptime(work_date_str, '%Y-%m-%d').date()
#             filters &= Q(date=work_date)
#         except ValueError:
#             pass

#     month_year_str = request.GET.get('month_year')
#     if month_year_str:
#         try:
#             month_start = datetime.strptime(month_year_str, '%Y-%m').date()
#             month_end = month_start + relativedelta(months=1) - timedelta(days=1)
#             filters &= Q(date__gte=month_start, date__lte=month_end)
#         except ValueError:
#             pass

#     week_start_date_str = request.GET.get('week_start_date')
#     if week_start_date_str:
#         try:
#             week_start = datetime.strptime(week_start_date_str, '%Y-%m-%d').date()
#             week_end = week_start + timedelta(days=6)
#             filters &= Q(date__gte=week_start, date__lte=week_end)
#         except ValueError:
#             pass

#     queryset = queryset.filter(filters).distinct().order_by('-date', 'user__full_name')

#     paginator = Paginator(queryset, 20)
#     page = request.GET.get('page', 1)

#     try:
#         page_obj = paginator.page(page)
#     except PageNotAnInteger:
#         page_obj = paginator.page(1)
#     except EmptyPage:
#         page_obj = paginator.page(paginator.num_pages)

#     status_choices = TimesheetEntry.STATUS_CHOICES

#     context = {
#         'page_obj': page_obj,
#         'all_users': CustomUser.objects.order_by('full_name').all(),
#         'all_teams': Team.objects.order_by('title').all(),
#         'all_projects': Project.objects.order_by('name').all(),
#         'status_choices': status_choices,
#         'current_params': request.GET.urlencode(),
#     }

#     return render(request, 'time_sheets.html', context)

from django.shortcuts import render
from django.db.models import Sum, Q, Prefetch
from django.contrib.auth.decorators import user_passes_test
from django.urls import reverse_lazy
from django.core.paginator import Paginator, EmptyPage, PageNotAnInteger
from datetime import datetime, timedelta
from dateutil.relativedelta import relativedelta
from .models import Timesheet, TimesheetEntry, CustomUser, Team, Project

@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def timesheet(request, scheduled=None):
    # 1. Capture Filter Parameters
    project_pk = request.GET.get('project_pk')
    user_pk = request.GET.get('user_pk')
    team_pk = request.GET.get('team_pk')
    work_date_str = request.GET.get('work_date')
    month_year_str = request.GET.get('month_year')
    week_start_date_str = request.GET.get('week_start_date')

    # 2. Build the Task Filter (used for Sum calculations and Main row filtering)
    task_specific_filter = Q()
    if project_pk:
        task_specific_filter &= Q(tasks__project__pk=project_pk)
    
    if scheduled:
        task_specific_filter &= Q(tasks__is_scheduled=True)
    else:
        task_specific_filter &= Q(tasks__is_scheduled=False)

    # 3. Build General Filters (for User/Team/Date)
    main_filters = Q()
    if user_pk:
        main_filters &= Q(user__pk=user_pk)
    if team_pk:
        main_filters &= Q(user__team__pk=team_pk)

    # Date Logic
    if work_date_str:
        try:
            main_filters &= Q(date=datetime.strptime(work_date_str, '%Y-%m-%d').date())
        except ValueError: pass
    elif month_year_str:
        try:
            start = datetime.strptime(month_year_str, '%Y-%m').date()
            end = start + relativedelta(months=1) - timedelta(days=1)
            main_filters &= Q(date__gte=start, date__lte=end)
        except ValueError: pass
    elif week_start_date_str:
        try:
            start = datetime.strptime(week_start_date_str, '%Y-%m-%d').date()
            main_filters &= Q(date__gte=start, date__lte=start + timedelta(days=6))
        except ValueError: pass

    # 4. Define Prefetch logic (controls which task badges appear in the table)
    inner_qs_filter = Q(project__pk=project_pk) if project_pk else Q()
    if scheduled:
        inner_qs_filter &= Q(is_scheduled=True)
    else:
        inner_qs_filter &= Q(is_scheduled=False)

    prefetch_tasks = Prefetch(
        'tasks',
        queryset=TimesheetEntry.objects.filter(inner_qs_filter).select_related('project')
    )

    # 5. Build QuerySet with Annotations
    queryset = Timesheet.objects.select_related('user', 'user__team').prefetch_related(prefetch_tasks)
    
    if request.user.role == 'leader':
        queryset = queryset.filter(user__team=request.user.team)

    # Apply filters and calculate conditional sums
    queryset = queryset.filter(main_filters).filter(task_specific_filter).annotate(
        total_hours=Sum('tasks__hours', filter=task_specific_filter),
        onsite_abroad_hours=Sum(
            'tasks__hours', 
            filter=task_specific_filter & Q(tasks__onsite_abroad=True)
        ),
        onsite_egypt_hours=Sum(
            'tasks__hours', 
            filter=task_specific_filter & Q(tasks__onsite_Egypt=True)
        ),
    ).distinct().order_by('-date', 'user__full_name')

    export_queryset = models.Timesheet.objects.filter(
    id__in=queryset.values_list('id', flat=True)
        )
    if request.method == "POST":
        if "export_csv" in request.POST:
            return export_timesheets_csv(export_queryset)
    
    # 6. Pagination & Parameter Cleanup
    paginator = Paginator(queryset, 20)
    page = request.GET.get('page', 1)
    try:
        page_obj = paginator.page(page)
    except (PageNotAnInteger, EmptyPage):
        page_obj = paginator.page(1)

    # Cleanup GET parameters to prevent 'page=1&page=2' in URL
    query_params = request.GET.copy()
    if 'page' in query_params:
        query_params.pop('page')

    context = {
        'page_obj': page_obj,
        'all_users': CustomUser.objects.order_by('full_name').all(),
        'all_teams': Team.objects.order_by('title').all(),
        'all_projects': Project.objects.order_by('name').all(),
        'current_params': query_params.urlencode(),
    }
    return render(request, 'time_sheets.html', context)

@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def project_timesheets(request, pk):
    """
    Displays a list of aggregated Timesheet records (daily logs) for a specific project.
    """
    # 1. Fetch the specific Project
    project = get_object_or_404(Project, pk=pk)
    
    # 2. Start with Timesheet model, filtered to include only those 
    #    that have at least one TimesheetEntry (task) linked to this project.
    # .distinct() is crucial here to prevent duplicate Timesheets
    queryset = Timesheet.objects.filter(tasks__project=project).select_related(
        'user'
    ).distinct()

    # 3. Conditional Aggregation and Annotation
    queryset = queryset.annotate(
        # Aggregate the sum of ALL hours in this Timesheet (even from other projects)
        total_hours=Sum('tasks__hours'),
        
        # Calculate status counts for all tasks in this Timesheet
        rejected_count=Count('tasks', filter=Q(tasks__status='REJECTED')),
        inprogress_count=Count('tasks', filter=Q(tasks__status='Inprogress')),
        approved_count=Count('tasks', filter=Q(tasks__status='APPROVED')),
        total_task_count=Count('tasks')
    ).annotate(
        # Determine a single summary status for the Timesheet
        summary_status=Case(
            When(rejected_count__gt=0, then=Value('REJECTED')),
            When(inprogress_count__gt=0, then=Value('PENDING')),
            When(approved_count=F('total_task_count'), total_task_count__gt=0, then=Value('APPROVED')),
            default=Value('MIXED'),
            output_field=CharField()
        )
    )

    # 4. Apply Filters (these filter the resulting Timesheet objects)
    filters = Q()

    # Employee Filter
    user_pk = request.GET.get('user_pk')
    if user_pk: filters &= Q(user__pk=user_pk)
    
    # Status Filter (Checks if AT LEAST ONE entry in the Timesheet matches the status)
    status = request.GET.get('status')
    if status: filters &= Q(tasks__status=status)

    # Date Range Filtering
    start_date_str = request.GET.get('start_date')
    if start_date_str: 
        try:
            datetime.strptime(start_date_str, '%Y-%m-%d')
            filters &= Q(date__gte=start_date_str)
        except ValueError: pass

    end_date_str = request.GET.get('end_date')
    if end_date_str: 
        try:
            datetime.strptime(end_date_str, '%Y-%m-%d')
            filters &= Q(date__lte=end_date_str)
        except ValueError: pass
            
    # Apply filters, ensure uniqueness again, and order
    queryset = queryset.filter(filters).distinct().order_by('-date', 'user__full_name')
    
    # 5. Calculate total hours *for this specific project* (Used in the header)
    #    We must calculate this on the TimesheetEntry model, not the aggregated Timesheet queryset
    project_entries = TimesheetEntry.objects.filter(project=project)
    project_total_hours = project_entries.aggregate(Sum('hours'))['hours__sum']

    # 6. Get unique users who have logged time on the project for the filter dropdown
    user_pks = project_entries.values_list('user__pk', flat=True).distinct()
    all_users_on_project = CustomUser.objects.filter(pk__in=user_pks).order_by('full_name')

    # 7. Pagination
    paginator = Paginator(queryset, 20) 
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    # 8. Context
    context = {
        'project': project,
        'page_obj': page_obj,
        'project_total_hours': project_total_hours, 
        'all_users_on_project': all_users_on_project,
        'status_choices': TimesheetEntry.STATUS_CHOICES,
    }
    
    return render(request, 'project_timesheets.html', context)



@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def timesheet_detail_entries(request, pk):
    """
    Displays all individual TimesheetEntry records (tasks) belonging 
    to a single Timesheet (daily log).

    This view is accessed via the link on the aggregated Timesheet lists 
    (like project_timesheets.html).
    """
    # 1. Fetch the Timesheet object (the daily log for a user/date)
    # The 'pk' argument is the primary key of the Timesheet object.
    timesheet = get_object_or_404(Timesheet, pk=pk)
    
    # 2. Retrieve all related TimesheetEntry tasks (tasks)
    # We use the related_name='tasks' defined on the ForeignKey in TimesheetEntry.
    # We use select_related for optimized lookup of the user and project linked to each entry.
    entries = timesheet.tasks.all().select_related('user', 'project')
    
    # 3. Calculate the total hours for this specific timesheet
    total_hours = entries.aggregate(Sum('hours'))['hours__sum']

    # 4. Context preparation
    # We pass the entries and the related Timesheet object itself.
    context = {
        'timesheet': timesheet,
        'entries': entries,
        'total_hours': total_hours,
        # Assuming TimesheetEntry.STATUS_CHOICES is defined and accessible
        'status_choices': TimesheetEntry.STATUS_CHOICES,
    }
    
    return render(request, 'timesheet_detail_entries.html', context)

import csv
from django.http import HttpResponse
def export_timesheets_csv(queryset):
    response = HttpResponse(content_type='text/csv')
    response['Content-Disposition'] = 'attachment; filename="timesheets.csv"'

    writer = csv.writer(response)

    writer.writerow([
        'Timesheet ID',
        'User',
        'Timesheet Date',
        'Entry ID',
        'Project',
        'Task Type',
        'Task Description',
        'Hours',
        'Work Date',
        'Status',
        'Scheduled',
        'Start Time',
        'End Time',
        'Onsite Abroad',
        'Onsite Egypt',
        'Created At'
    ])

    for timesheet in queryset.prefetch_related('tasks', 'tasks__project'):
        tasks = timesheet.tasks.all()

        if not tasks.exists():
            writer.writerow([
                timesheet.id,
                timesheet.user.username,
                timesheet.date,
                '', '', '', '', '', '', '', '', '', '', '', '', ''
            ])
            continue

        for entry in tasks:
            writer.writerow([
                timesheet.id,
                timesheet.user.username,
                timesheet.date,
                entry.id,
                entry.project.name if entry.project else '',
                entry.task_type,
                entry.task_description,
                entry.hours,
                entry.work_date,
                entry.status,
                entry.is_scheduled,
                entry.time_start,
                entry.time_end,
                entry.onsite_abroad,
                entry.onsite_Egypt,
                entry.created_at,
            ])

    return response

@login_required
def user_timesheets(request, scheduled=None):
    current_user = request.user
    
    # 1. Start with Timesheet objects filtered by the current user
    if scheduled:
        queryset = models.Timesheet.objects.filter(
            user=current_user, 
            tasks__is_scheduled=True
        ).select_related('user')
    else: 
        queryset = models.Timesheet.objects.filter(
            user=current_user, 
            tasks__is_scheduled=False
        ).select_related('user')
    
    # 2. Aggregation (Calculate total hours and summary status)
    queryset = queryset.annotate(
        total_hours=Sum('tasks__hours'),
        rejected_count=Count('tasks', filter=Q(tasks__status='REJECTED')),
        inprogress_count=Count('tasks', filter=Q(tasks__status='Inprogress')),
        approved_count=Count('tasks', filter=Q(tasks__status='APPROVED')),
        total_task_count=Count('tasks')
    ).annotate(
        summary_status=Case(
            When(rejected_count__gt=0, then=Value('REJECTED')),
            When(inprogress_count__gt=0, then=Value('PENDING')),
            When(approved_count=F('total_task_count'), total_task_count__gt=0, then=Value('APPROVED')),
            default=Value('MIXED'),
            output_field=CharField()
        )
    )

    # 3. Simple Date and Status Filtering
    filters = Q()
    
    work_date_str = request.GET.get('work_date')
    if work_date_str:
        try:
            work_date = datetime.strptime(work_date_str, '%Y-%m-%d').date()
            filters &= Q(date=work_date)
        except ValueError: 
            pass 

    status = request.GET.get('status')
    if status: 
        filters &= Q(tasks__status=status)
    
    # Apply filters and ensure distinct results for the paginator
    queryset = queryset.filter(filters).distinct().order_by('-date')
    export_queryset = models.Timesheet.objects.filter(
    id__in=queryset.values_list('id', flat=True)
        )
    if request.method == "POST":
        if "export_csv" in request.POST:
            return export_timesheets_csv(export_queryset)
    

    # 4. Pagination Logic
    paginator = Paginator(queryset, 20) 
    page_number = request.GET.get('page', 1)

    try:
        page_obj = paginator.page(page_number)
    except (PageNotAnInteger, EmptyPage):
        page_obj = paginator.page(1)

    # 5. Clean Query Parameters for Pagination Links
    # This prevents ?page=2&page=3&page=4 stacking in the URL
    query_params = request.GET.copy()
    if 'page' in query_params:
        del query_params['page']

    context = {
        'page_obj': page_obj,
        'current_user_view': True,
        'all_users': models.CustomUser.objects.none(),
        'all_teams': models.Team.objects.none(),
        'all_projects': models.Project.objects.filter(is_public=True, is_active=True),
        'status_choices': models.TimesheetEntry.STATUS_CHOICES,
        'current_params': query_params.urlencode(), # Only contains filters, not the page
    }

    return render(request, 'time_sheets.html', context)


@login_required
def my_timesheet_entries(request, pk):
    current_user = request.user
    timesheet = models.Timesheet.objects.get(pk=pk)
    queryset = timesheet.tasks.filter(user=current_user).select_related('project')
    
    filters = Q()

    project_pk = request.GET.get('project_pk')
    if project_pk:
        filters &= Q(project__pk=project_pk)
    
    status = request.GET.get('status')
    if status:
        filters &= Q(status=status)
    
    work_date_str = request.GET.get('work_date')
    if work_date_str:
        try:
            work_date = datetime.strptime(work_date_str, '%Y-%m-%d').date()
            filters &= Q(work_date=work_date)
        except ValueError:
            pass
            
    queryset = queryset.filter(filters).order_by('-work_date', '-created_at')

    user_projects = models.Project.objects.filter(
        entries__user=current_user
    ).distinct().order_by('name')

    paginator = Paginator(queryset, 20)
    page_number = request.GET.get('page', 1)

    try:
        page_obj = paginator.page(page_number)
    except PageNotAnInteger:
        page_obj = paginator.page(1)
    except EmptyPage:
        page_obj = paginator.page(paginator.num_pages)

    context = {
        'page_obj': page_obj,
        'user_projects': user_projects,
        'status_choices': models.TimesheetEntry.STATUS_CHOICES,
        'projects': Project.objects.all()
    }
    
    return render(request, 'mytime_sheets.html', context)


@login_required
def timesheet_entries(request, pk):
    timesheet = models.Timesheet.objects.get(pk=pk)
    current_user = timesheet.user
    
    queryset = timesheet.tasks.filter(is_scheduled=False).select_related('project')
    
    filters = Q()

    project_pk = request.GET.get('project_pk')
    if project_pk:
        filters &= Q(project__pk=project_pk)
    
    status = request.GET.get('status')
    if status:
        filters &= Q(status=status)
    
    work_date_str = request.GET.get('work_date')
    if work_date_str:
        try:
            work_date = datetime.strptime(work_date_str, '%Y-%m-%d').date()
            filters &= Q(work_date=work_date)
        except ValueError:
            pass
            
    queryset = queryset.filter(filters).order_by('-work_date', '-created_at')

    user_projects = models.Project.objects.filter(
        entries__user=current_user
    ).distinct().order_by('name')

    paginator = Paginator(queryset, 20)
    page_number = request.GET.get('page', 1)

    try:
        page_obj = paginator.page(page_number)
    except PageNotAnInteger:
        page_obj = paginator.page(1)
    except EmptyPage:
        page_obj = paginator.page(paginator.num_pages)

    context = {
        'page_obj': page_obj,
        'user_projects': user_projects,
        'status_choices': models.TimesheetEntry.STATUS_CHOICES,
        'projects': Project.objects.filter(is_public=True, is_active=True)
    }

    return render(request, 'mytime_sheets.html', context)



@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def add_project_cost(request):
    if request.method == "POST":
        data = request.POST
        pk = data.get("project_pk")
        project = get_object_or_404(models.Project, pk=pk)
        user = models.CustomUser.objects.get(pk=data.get("employee"))
        obj = models.ProjectCost.objects.create(user=user,
                                           project=project,
                                            amount = data.get("amount"),
                                           notes = data.get("notes"),
                                           currency = data.get("currency"))
        if data.get("cost_type") == "Other":
            obj.cost_type = data.get("other_cost_type")
        else:
            obj.cost_type = data.get("cost_type")
        obj.save()
        messages.success(request, 'The Cost Added Successfuly...')
        return redirect('projects')
    

@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def reports(request):
    return render(request, 'reports.html', {})



HOURS_PER_DAY = 8


def get_date_range(period, start_date_str, end_date_str):
    """Calculates start and end dates based on period string or custom dates."""
    today = date.today()
    start_date = None
    end_date = None

    if period == 'custom' and start_date_str and end_date_str:
        try:
            start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
            end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
        except ValueError:
            pass # Invalid date format, return None

    elif period == 'month':
        start_date = today.replace(day=1)
        end_date = today

    elif period == 'quarter':
        current_quarter = (today.month - 1) // 3 + 1
        start_month = 3 * current_quarter - 2
        start_date = today.replace(month=start_month, day=1)
        end_date = today
    
    elif period == 'year':
        start_date = today.replace(month=1, day=1)
        end_date = today
        
    return start_date, end_date

def apply_date_filters(queryset, start_date, end_date):
    """Applies date filtering to a TimesheetEntry queryset."""
    if start_date:
        queryset = queryset.filter(work_date__gte=start_date)
    if end_date:
        queryset = queryset.filter(work_date__lte=end_date)
    return queryset



@login_required
def reports_dashboard(request):
    """Report Hub Page View"""
    # Simply renders the navigation dashboard
    return render(request, 'reports_dashboard.html', {})


# @login_required
# def reports_man_days(request):
#     """Report 1: Man-Days & Utilization"""
    
#     period = request.GET.get('period', 'month')
#     user_pk = request.GET.get('user_pk')
#     start_date_str = request.GET.get('start_date')
#     end_date_str = request.GET.get('end_date')
#     start_date, end_date = get_date_range(period, start_date_str, end_date_str)
    
#     # Start with all TimesheetEntry objects
#     queryset = TimesheetEntry.objects.all()
    
#     if user_pk:
#         queryset = queryset.filter(user__pk=user_pk)
    
#     # Filter entries by date range
#     queryset = apply_date_filters(queryset, start_date, end_date)
    
#     # --- Global Metrics Calculation ---
    
#     total_logged_hours = queryset.aggregate(Sum('hours'))['hours__sum'] or 0
    
#     # Identify unique active employees who logged time in the period
#     active_employees_pks = queryset.values_list('user__pk', flat=True).distinct()
#     active_employees_count = len(active_employees_pks)
    
#     # Calculate duration of the period in days
#     if start_date and end_date:
#         period_days = (end_date - start_date).days + 1
#     else:
#         # Fallback for approximate defaults if custom range not selected
#         period_days = 30 
        
#     # Total available hours calculation based on *all* users if no filter is set, 
#     # but we use active employees count for better accuracy within the logged data set.
#     total_available_hours = active_employees_count * period_days * HOURS_PER_DAY
    
#     # Utilization Rate
#     utilization_rate = (total_logged_hours / total_available_hours) * 100 if total_available_hours > 0 else 0
    
#     # Man-Days are just total available hours divided by HOURS_PER_DAY
#     total_man_days = total_available_hours / HOURS_PER_DAY
#     total_overtime = 0 # Complex calculation, simplified to 0 for now
    
#     # --- Employee Breakdown Data ---
#     # We annotate CustomUser objects with their totals from the filtered queryset
#     employee_data = CustomUser.objects.filter(pk__in=active_employees_pks).annotate(
#         # FIX: Changed 'timesheetentry__in=queryset' to 'timesheets__in=queryset'
#         total_hours=Sum('timesheets__hours', filter=Q(timesheets__in=queryset)),
#         total_days_logged=Count('timesheets__work_date', distinct=True, filter=Q(timesheets__in=queryset)),
#         last_log_date=Max('timesheets__work_date', filter=Q(timesheets__in=queryset)),
#     ).filter(total_hours__isnull=False).annotate(
#         # New calculation: total_hours divided by 8 (hours per day) for the unit
#         work_unit_days=F('total_hours') / HOURS_PER_DAY,
#         # Utilization: total_hours divided by (total_days_logged * 8)
#         utilization_percent=Case(
#             When(total_days_logged__gt=0, then=(F('total_hours') / (F('total_days_logged') * HOURS_PER_DAY)) * 100),
#             default=Value(0.0),
#             output_field=DecimalField()
#         )
#     ).order_by('-total_hours')
    
#     context = {
#         'total_logged_hours': round(total_logged_hours, 2),
#         'total_man_days': round(total_man_days, 2),
#         'utilization_rate': round(utilization_rate, 2),
#         'total_overtime': round(total_overtime, 2),
#         'employee_data': employee_data,
#         'all_users': CustomUser.objects.order_by('full_name').all(),
#     }
#     return render(request, 'man_days_utilization_report.html', context)

from django.shortcuts import render
from django.contrib.auth.decorators import login_required
from django.db.models import Sum, Count, Q
from django.core.paginator import Paginator
from datetime import time, datetime

def get_post_5pm_overtime(entries):
    """Calculates hours worked after 17:00 (5:00 PM)"""
    ot_hours = 0.0
    cutoff = time(17, 0)
    for entry in entries:
        if entry.time_start and entry.time_end and entry.time_end > cutoff:
            actual_ot_start = max(entry.time_start, cutoff)
            dummy = datetime.today()
            start_dt = datetime.combine(dummy, actual_ot_start)
            end_dt = datetime.combine(dummy, entry.time_end)
            duration = (end_dt - start_dt).total_seconds() / 3600
            ot_hours += max(0, duration)
    return ot_hours

from django.http import HttpResponse
from django.template.loader import render_to_string
# If using xhtml2pdf: 
# from xhtml2pdf import pisa 

# @login_required
# def reports_daily_man_days(request):
#     STANDARD_HOURS = 8.0
#     user_pk = request.GET.get('user_pk')
#     project_pk = request.GET.get('project_pk')
#     start_date = request.GET.get('start_date')
#     end_date = request.GET.get('end_date')
#     export_pdf = request.GET.get('export_pdf')

#     # 1. Base Query
#     queryset = TimesheetEntry.objects.filter(is_scheduled=False).exclude(task_type="study").select_related('project', 'user')

#     # 2. Apply Filters
#     if user_pk:
#         queryset = queryset.filter(user__pk=user_pk)
#     if project_pk:
#         queryset = queryset.filter(project__pk=project_pk)
#     if start_date:
#         queryset = queryset.filter(work_date__gte=start_date)
#     if end_date:
#         queryset = queryset.filter(work_date__lte=end_date)

#     # 3. Aggregation
#     daily_stats = queryset.values(
#         'work_date', 'user__full_name', 'user__pk'
#     ).annotate(
#         total_daily_hours=Sum('hours'),
#         egypt_hours=Sum('hours', filter=Q(onsite_Egypt=True)),
#         abroad_hours=Sum('hours', filter=Q(onsite_abroad=True)),
#     ).order_by('-work_date', 'user__full_name')

#     refined_entries = []
#     totals = {'hours': 0.0, 'ot': 0.0, 'egypt': 0.0, 'abroad': 0.0}

#     for day in daily_stats:
#         # Get tasks for this user/day to calculate OT and list projects
#         day_entries = queryset.filter(work_date=day['work_date'], user__pk=day['user__pk'])
        
#         # Calculate unique projects and their individual hours for this row
#         project_details = day_entries.values('project__name').annotate(p_hours=Sum('hours'))
        
#         post_5_ot = float(get_post_5pm_overtime(day_entries))
#         logged = float(day['total_daily_hours'] or 0)
#         work_hours_for_manday = max(0, logged - post_5_ot)
        
#         entry_data = {
#             'work_date': day['work_date'],
#             'user_full_name': day['user__full_name'],
#             'total_hours': logged,
#             'overtime': post_5_ot,
#             'egypt_hours': float(day['egypt_hours'] or 0),
#             'abroad_hours': float(day['abroad_hours'] or 0),
#             'man_day_display': f"{work_hours_for_manday:g}/{STANDARD_HOURS:g}",
#             'projects': project_details, # List of projects with their specific hours
#         }
        
#         totals['hours'] += logged
#         totals['ot'] += post_5_ot
#         totals['egypt'] += entry_data['egypt_hours']
#         totals['abroad'] += entry_data['abroad_hours']
#         refined_entries.append(entry_data)

#     # 4. Handle PDF Export
#     if export_pdf:
#         context = {'entries': refined_entries, 'totals': totals, 'is_pdf': True}
#         html = render_to_string('man_days_pdf_template.html', context)
#         response = HttpResponse(content_type='application/pdf')
#         response['Content-Disposition'] = 'attachment; filename="man_days_report.pdf"'
#         # pisa.CreatePDF(html, dest=response) # Uncomment if using xhtml2pdf
#         return response

#     # 5. Pagination
#     paginator = Paginator(refined_entries, 20)
#     page_obj = paginator.get_page(request.GET.get('page'))

#     context = {
#         'page_obj': page_obj,
#         'totals': totals,
#         'all_users': CustomUser.objects.all().order_by('full_name'),
#         'all_projects': Project.objects.filter(is_active=True).order_by('name'),
#     }
#     return render(request, 'man_days_utilization_report.html', context)

from django.db.models import Sum, Q
from django.shortcuts import render
from django.contrib.auth.decorators import login_required
from django.core.paginator import Paginator
from django.template.loader import render_to_string
from django.http import HttpResponse

@login_required
def reports_daily_man_days(request):
    STANDARD_HOURS = 8.0
    user_pk = request.GET.get('user_pk')
    project_pk = request.GET.get('project_pk')
    start_date = request.GET.get('start_date')
    end_date = request.GET.get('end_date')
    work_location = request.GET.get('work_location') # New Filter
    export_pdf = request.GET.get('export_pdf')

    # 1. Base Query
    queryset = TimesheetEntry.objects.filter(
        is_scheduled=False
    ).exclude(task_type="study").select_related('project', 'user')

    # 2. Apply Filters
    if user_pk:
        queryset = queryset.filter(user__pk=user_pk)
    if project_pk:
        queryset = queryset.filter(project__pk=project_pk)
    if start_date:
        queryset = queryset.filter(work_date__gte=start_date)
    if end_date:
        queryset = queryset.filter(work_date__lte=end_date)
    
    # Task Type Logic: Abroad vs Remotely (Office)
    if work_location == 'abroad':
        queryset = queryset.filter(onsite_abroad=True)
    elif work_location == 'remote':
        queryset = queryset.filter(onsite_abroad=False)

    # 3. Aggregation
    daily_stats = queryset.values(
        'work_date', 'user__full_name', 'user__pk'
    ).annotate(
        total_daily_hours=Sum('hours'),
        egypt_hours=Sum('hours', filter=Q(onsite_Egypt=True)),
        abroad_hours=Sum('hours', filter=Q(onsite_abroad=True)),
    ).order_by('-work_date', 'user__full_name')

    refined_entries = []
    totals = {'hours': 0.0, 'ot': 0.0, 'egypt': 0.0, 'abroad': 0.0}

    for day in daily_stats:
        # Get tasks for this specific user/day from the already filtered queryset
        day_entries = queryset.filter(work_date=day['work_date'], user__pk=day['user__pk'])
        
        project_details = day_entries.values('project__name').annotate(p_hours=Sum('hours'))
        
        # OT Calculation (Assumes your helper function handles the filtered entries)
        post_5_ot = float(get_post_5pm_overtime(day_entries))
        logged = float(day['total_daily_hours'] or 0)
        work_hours_for_manday = max(0, logged - post_5_ot)
        
        entry_data = {
            'work_date': day['work_date'],
            'user_full_name': day['user__full_name'],
            'total_hours': logged,
            'overtime': post_5_ot,
            'egypt_hours': float(day['egypt_hours'] or 0),
            'abroad_hours': float(day['abroad_hours'] or 0),
            'man_day_display': f"{work_hours_for_manday:g}/{STANDARD_HOURS:g}",
            'projects': project_details,
        }
        
        totals['hours'] += logged
        totals['ot'] += post_5_ot
        totals['egypt'] += entry_data['egypt_hours']
        totals['abroad'] += entry_data['abroad_hours']
        refined_entries.append(entry_data)

    # 4. Handle PDF Export
    if export_pdf:
        context = {'entries': refined_entries, 'totals': totals, 'is_pdf': True}
        html = render_to_string('man_days_pdf_template.html', context)
        response = HttpResponse(content_type='application/pdf')
        response['Content-Disposition'] = 'attachment; filename="man_days_report.pdf"'
        return response

    # 5. Pagination
    paginator = Paginator(refined_entries, 20)
    page_obj = paginator.get_page(request.GET.get('page'))

    context = {
        'page_obj': page_obj,
        'totals': totals,
        'all_users': CustomUser.objects.all().order_by('full_name'),
        'all_projects': Project.objects.filter(is_active=True).order_by('name'),
        'search_query': request.GET.urlencode(), # To preserve filters in pagination
    }
    return render(request, 'man_days_utilization_report.html', context)

# @login_required
# def reports_man_days(request):
#     # 1. Base Setup
#     STANDARD_HOURS = 8.0
#     queryset = TimesheetEntry.objects.filter(is_scheduled=False)

#     # 2. Apply Filters (matching your HTML form names)
#     user_pk = request.GET.get('user_pk')
#     project_pk = request.GET.get('project_pk')
#     start_date = request.GET.get('start_date')
#     end_date = request.GET.get('end_date')

#     if user_pk:
#         queryset = queryset.filter(user__pk=user_pk)
#     if project_pk:
#         queryset = queryset.filter(project__pk=project_pk)
#     if start_date:
#         queryset = queryset.filter(work_date__gte=start_date)
#     if end_date:
#         queryset = queryset.filter(work_date__lte=end_date)

#     # 3. Aggregate Daily Data (Grouping by User and Date)
#     daily_stats = queryset.values(
#         'work_date', 'user__full_name', 'user__username', 'user__pk'
#     ).annotate(
#         total_daily_hours=Sum('hours'),
#         project_count=Count('project', distinct=True)
#     ).order_by('-work_date')

#     # 4. Refine Data for Overtime Logic
#     refined_entries = []
#     total_hours_sum = 0.0
#     total_overtime_sum = 0.0

#     for day in daily_stats:
#         # Get individual tasks to calculate clock-based overtime
#         day_entries = queryset.filter(
#             work_date=day['work_date'], 
#             user__pk=day['user__pk']
#         )
        
#         # Calculate Overtime (Post-5PM)
#         post_5_ot = get_post_5pm_overtime(day_entries)
        
#         # Calculate Capacity difference (for your Under/Over badge)
#         logged = float(day['total_daily_hours'] or 0)
        
#         # We use 'overtime_hours' as the key because your HTML uses 'entry.overtime_hours'
#         day_row = {
#             'work_date': day['work_date'],
#             'user__full_name': day['user__full_name'],
#             'user__username': day['user__username'],
#             'project_count': day['project_count'],
#             'total_daily_hours': logged,
#             'overtime_hours': post_5_ot if logged >= STANDARD_HOURS else (logged - STANDARD_HOURS),
#         }
        
#         # Update Global Totals
#         total_hours_sum += logged
#         total_overtime_sum += post_5_ot
#         refined_entries.append(day_row)

#     # 5. Pagination
#     paginator = Paginator(refined_entries, 20)
#     page_obj = paginator.get_page(request.GET.get('page'))

#     context = {
#         'page_obj': page_obj,
#         'total_hours_sum': total_hours_sum,
#         'total_overtime_sum': total_overtime_sum,
#         'total_standard_sum': len(refined_entries) * STANDARD_HOURS,
#         'standard_day_hours': STANDARD_HOURS,
#         'all_users': CustomUser.objects.order_by('full_name').all(),
#         'all_projects': Project.objects.filter(is_active=True),
#         'project_pk': project_pk,
#     }
#     return render(request, 'man_days_utilization_report.html', context)


PRIMARY_CURRENCY = 'EGP' # Example constant
PAGINATE_BY = PAGE_SIZE

@login_required
def reports_project_cost(request):
    """
    Project Cost Report View: Filters cost entries, calculates total, and paginates.
    """
    
    # 1. Get filter parameters
    project_pk = request.GET.get('project_pk')
    user_pk = request.GET.get('user_pk')
    
    # 2. Build the initial queryset
    # Use .select_related() for performance when accessing foreign key fields in the template
    queryset = ProjectCost.objects.all().select_related('project', 'user').order_by('-pk')
    
    # 3. Apply Filters
    if project_pk:
        queryset = queryset.filter(project__pk=project_pk)
    
    if user_pk:
        queryset = queryset.filter(user__pk=user_pk)
        
    # 4. Total Cost Calculation
    # Note: This is simplified! For a multi-currency system, 
    # you would need to convert all amounts to the PRIMARY_CURRENCY 
    # before summing them up (e.g., using an exchange rate table).
    total_cost_aggregation = queryset.aggregate(
        total=Sum('amount', filter=Q(currency=PRIMARY_CURRENCY))
    )
    # If using a single currency, you can remove the Q filter.
    
    total_cost = total_cost_aggregation['total'] or Decimal('0.00')

    # 5. Pagination
    paginator = Paginator(queryset, PAGINATE_BY)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)
    
    # 6. Context Data
    context = {
        'page_obj': page_obj,
        'total_cost': total_cost,
        'primary_currency': PRIMARY_CURRENCY,
        # Pass filter options to the template
        'all_projects': Project.objects.order_by('name').all(),
        'all_users': CustomUser.objects.order_by('full_name', 'username').all(),
    }
    
    return render(request, 'project_costs.html', context)

@login_required
def reports_project_cost_summary(request):
    """Report 2: Project Cost Summary"""
    
    period = request.GET.get('period', 'all')
    project_pk = request.GET.get('project_pk')
    user_pk = request.GET.get('user_pk')
    start_date, end_date = get_date_range(period, request.GET.get('start_date'), request.GET.get('end_date'))

    # Filter Timesheet Entries (for Man-Hours)
    entry_queryset = TimesheetEntry.objects.filter(is_scheduled=False)
    # Filter Project Costs (External Expenses)
    cost_queryset = ProjectCost.objects.all()
    
    # Apply Filters
    if project_pk:
        entry_queryset = entry_queryset.filter(project__pk=project_pk)
        cost_queryset = cost_queryset.filter(project__pk=project_pk)
    if user_pk:
        entry_queryset = entry_queryset.filter(user__pk=user_pk)
        cost_queryset = cost_queryset.filter(user__pk=user_pk)
        
    entry_queryset = apply_date_filters(entry_queryset, start_date, end_date)
    # ProjectCost model needs a date field to filter by date (assuming 'created_at' or similar)
    # cost_queryset = apply_date_filters(cost_queryset, start_date, end_date) 
    
    # --- Global Metrics ---
    total_logged_hours = entry_queryset.aggregate(Sum('hours'))['hours__sum'] or 0
    total_external_cost = cost_queryset.aggregate(Sum('amount'))['amount__sum'] or 0
    
    # Cost calculations removed as per request, setting to zero or linking to hours
    total_man_hour_cost = 0 
    grand_total_cost = total_external_cost # Man-hour cost removed
    
    # --- Project Breakdown Data ---
    
    # 1. Aggregate Time/Cost by Project
    project_time_data = entry_queryset.values('project__name', 'project__pk').annotate(
        total_hours=Sum('hours'),
        # Man hour cost field removed
    )
    
    # 2. Aggregate External Costs by Project
    project_expense_data = cost_queryset.values('project__name', 'project__pk').annotate(
        external_cost=Sum('amount'),
    )
    
    # 3. Combine Data (Simplification: just calculating totals)
    project_cost_data = []
    
    # Fetch all unique project IDs involved in the filtered data
    project_pks = set(p['project__pk'] for p in project_time_data) | set(p['project__pk'] for p in project_expense_data)
    
    for pk in project_pks:
        time_data = next((item for item in project_time_data if item['project__pk'] == pk), {})
        expense_data = next((item for item in project_expense_data if item['project__pk'] == pk), {})
        
        hours = time_data.get('total_hours', 0)
        external_cost = expense_data.get('external_cost', 0)
        
        # Man hour cost is zero as per request
        man_hour_cost = 0 
        total_cost = external_cost # Cost is just external cost
        
        project_cost_data.append({
            'project_name': time_data.get('project__name') or expense_data.get('project__name'),
            'total_hours': round(hours, 2),
            'man_hour_cost': round(man_hour_cost, 2),
            'external_cost': round(external_cost, 2),
            'total_cost': round(total_cost, 2),
        })


    context = {
        'total_logged_hours': round(total_logged_hours, 2),
        'total_external_cost': round(total_external_cost, 2),
        'total_man_hour_cost': round(total_man_hour_cost, 2),
        'grand_total_cost': round(grand_total_cost, 2),
        'project_cost_data': sorted(project_cost_data, key=lambda x: x['total_cost'], reverse=True),
        'all_projects': Project.objects.order_by('name').all(),
        'all_users': CustomUser.objects.order_by('full_name').all(),
    }
    return render(request, 'project_cost_summary_report.html', context)


@login_required
def reports_status_compliance(request):
    """Report 3: Timesheet Status & Compliance"""
    
    period = request.GET.get('period', 'month')
    user_pk = request.GET.get('user_pk')
    start_date, end_date = get_date_range(period, request.GET.get('start_date'), request.GET.get('end_date'))

    queryset = TimesheetEntry.objects.filter(is_scheduled=False)
    
    if user_pk:
        queryset = queryset.filter(user__pk=user_pk)
        
    queryset = apply_date_filters(queryset, start_date, end_date)
    
    # --- Global Metrics ---
    
    global_counts = queryset.aggregate(
        total=Count('id'),
        approved_count=Count(Case(When(status='APPROVED', then=1))),
        pending_count=Count(Case(When(Q(status='Inprogress') | Q(status='DRAFT'), then=1))),
        rejected_count=Count(Case(When(status='REJECTED', then=1))),
    )
    
    total_entries = global_counts['total'] or 0
    approved_count = global_counts['approved_count'] or 0
    pending_count = global_counts['pending_count'] or 0
    rejected_count = global_counts['rejected_count'] or 0
    
    approved_percent = (approved_count / total_entries) * 100 if total_entries > 0 else 0
    
    # --- Employee Breakdown Data ---
    
    compliance_data_qs = CustomUser.objects.filter(is_active=True).annotate(
        # FIX: Changed 'timesheetentry__in=queryset' to 'timesheets__in=queryset'
        total_entries=Count('timesheets', filter=Q(timesheets__in=queryset)),
        approved_count=Count(Case(When(Q(timesheets__in=queryset) & Q(timesheets__status='APPROVED'), then=1))),
        pending_count=Count(Case(When(Q(timesheets__in=queryset) & (Q(timesheets__status='Inprogress') | Q(timesheets__status='DRAFT')), then=1))),
        rejected_count=Count(Case(When(Q(timesheets__in=queryset) & Q(timesheets__status='REJECTED'), then=1))),
    ).filter(total_entries__gt=0).annotate(
        approved_percent=Case(
            When(total_entries__gt=0, then=(F('approved_count') / F('total_entries')) * 100),
            default=Value(0.0),
            output_field=DecimalField()
        )
    ).order_by('-total_entries')

    compliance_data = []
    for user in compliance_data_qs:
        compliance_data.append({
            'employee_name': user.full_name or user.username,
            'total_entries': user.total_entries,
            'approved_percent': round(user.approved_percent, 2),
            'pending_count': user.pending_count,
            'rejected_count': user.rejected_count,
        })
        
    context = {
        'total_entries': total_entries,
        'approved_percent': round(approved_percent, 2),
        'pending_count': pending_count,
        'rejected_count': rejected_count,
        'compliance_data': compliance_data,
        'all_users': CustomUser.objects.order_by('full_name').all(),
    }
    return render(request, 'status_compliance_report.html', context)


@login_required
def reports_employee_activity(request):
    """Report 4: Employee Activity Log"""
    
    period = request.GET.get('period', 'month')
    user_pk = request.GET.get('user_pk')
    project_pk = request.GET.get('project_pk')
    start_date, end_date = get_date_range(period, request.GET.get('start_date'), request.GET.get('end_date'))
    
    selected_employee = None
    activity_data = []
    total_logged_hours = 0
    approved_percent = 0
    distinct_project_count = 0

    if user_pk:
        try:
            selected_employee = CustomUser.objects.get(pk=user_pk)
            
            queryset = TimesheetEntry.objects.filter(user=selected_employee)
            
            if project_pk:
                queryset = queryset.filter(project__pk=project_pk)
            
            queryset = apply_date_filters(queryset, start_date, end_date)
            
            # --- Key Metrics ---
            metrics = queryset.aggregate(
                total_hours=Sum('hours'),
                total_entries=Count('id'),
                approved_count=Count(Case(When(status='APPROVED', then=1))),
                distinct_projects=Count('project', distinct=True)
            )
            
            total_logged_hours = metrics['total_hours'] or 0
            total_entries = metrics['total_entries'] or 0
            approved_count = metrics['approved_count'] or 0
            distinct_project_count = metrics['distinct_projects'] or 0
            
            approved_percent = (approved_count / total_entries) * 100 if total_entries > 0 else 0
            
            # --- Detailed Activity Table Data ---
            activity_data = queryset.select_related('project').order_by('-work_date')
            
            # Prepare data for template (list of dicts)
            activity_data = [{
                'work_date': entry.work_date,
                'project_name': entry.project.name,
                'task_type': entry.task_type,
                'hours': entry.hours,
                'status': entry.status,
            } for entry in activity_data]

        except CustomUser.DoesNotExist:
            selected_employee = None


    context = {
        'selected_employee': selected_employee,
        'total_logged_hours': round(total_logged_hours, 2),
        'approved_percent': round(approved_percent, 2),
        'distinct_project_count': distinct_project_count,
        'activity_data': activity_data,
        'all_users': CustomUser.objects.order_by('full_name').all(),
        'all_projects': Project.objects.order_by('name').all(),
    }
    return render(request, 'employee_activity_report.html', context)


@login_required
def reports_public_project_health(request):
    """Report 5: Public Project Health"""
    
    period = request.GET.get('period', 'all')
    project_pk = request.GET.get('project_pk')
    start_date, end_date = get_date_range(period, request.GET.get('start_date'), request.GET.get('end_date'))
    
    # 1. Base Query for Public Projects
    public_projects_qs = Project.objects.filter(is_public=True)
    if project_pk:
        public_projects_qs = public_projects_qs.filter(pk=project_pk)
    
    # 2. Filter Timesheet Entries and Costs belonging to these public projects
    entry_queryset = TimesheetEntry.objects.filter(project__in=public_projects_qs)
    cost_queryset = ProjectCost.objects.filter(project__in=public_projects_qs)

    entry_queryset = apply_date_filters(entry_queryset, start_date, end_date)
    # Assuming ProjectCost needs filtering, but ProjectCost model lacks 'date' field in definition
    # For safety, we rely on the Project filter alone if a date field isn't available on ProjectCost.
    
    # --- Global Metrics ---
    total_public_hours = entry_queryset.aggregate(Sum('hours'))['hours__sum'] or 0
    total_public_external_cost = cost_queryset.aggregate(Sum('amount'))['amount__sum'] or 0
    
    # Cost calculations removed/simplified
    total_public_man_cost = 0 # Man-hour cost estimation removed
    
    # --- Project Breakdown Data ---
    
    project_health_data = public_projects_qs.annotate(
        # Aggregate hours logged against this project
        total_hours=Sum('entries__hours', filter=Q(entries__in=entry_queryset)),
        # Aggregate external costs logged against this project
        external_cost=Sum('projectcost__amount', filter=Q(projectcost__in=cost_queryset)),
    ).filter(Q(total_hours__isnull=False) | Q(external_cost__isnull=False)).annotate(
        # Man-hour cost estimation removed/simplified to 0
        man_hour_cost=Value(0, output_field=DecimalField()),
        grand_total_cost=F('external_cost'),
    ).order_by('-grand_total_cost')

    public_project_data = []
    for project in project_health_data:
        public_project_data.append({
            'project_name': project.name,
            'total_hours': round(project.total_hours or 0, 2),
            'man_hour_cost': round(project.man_hour_cost or 0, 2),
            'external_cost': round(project.external_cost or 0, 2),
            'grand_total_cost': round(project.grand_total_cost or 0, 2),
        })

    context = {
        'public_project_count': public_projects_qs.count(),
        'total_public_hours': round(total_public_hours, 2),
        'total_public_man_cost': round(total_public_man_cost, 2),
        'total_public_external_cost': round(total_public_external_cost, 2),
        'public_project_data': public_project_data,
        'public_projects': Project.objects.filter(is_public=True).order_by('name').all(),
    }
    return render(request, 'public_project_health_report.html', context)

PAGINATE_BY = PAGE_SIZE 

def get_valid_date(date_str):
    """Safely converts a string to a date object."""
    if date_str:
        try:
            return date.fromisoformat(date_str)
        except ValueError:
            pass
    return None

# --- Updated View Function ---

# @login_required
# def reports_daily_man_days(request):
#     """
#     Report: Daily Man-Days Breakdown, aggregating timesheet entries by user and day.
#     """
    
#     # 1. Get filter parameters
#     user_pk = request.GET.get('user_pk')
#     project_pk = request.GET.get('project_pk')
#     start_date_str = request.GET.get('start_date')
#     end_date_str = request.GET.get('end_date')
    
#     start_date = get_valid_date(start_date_str)
#     end_date = get_valid_date(end_date_str)

#     # 2. Base Queryset (TimesheetEntry)
#     queryset = TimesheetEntry.objects.filter(is_scheduled=False)
    
#     # 3. Apply Filters
#     if user_pk:
#         queryset = queryset.filter(user__pk=user_pk)
    
#     if project_pk:
#         # Important: If filtering by project, the aggregation will only show hours
#         # related to that project on the specific day.
#         queryset = queryset.filter(project__pk=project_pk)
        
#     if start_date:
#         queryset = queryset.filter(work_date__gte=start_date)
    
#     if end_date:
#         queryset = queryset.filter(work_date__lte=end_date)
        
#     # 4. Core Aggregation: Group by User and Day
#     # We select fields needed for display and then annotate the aggregated values
#     daily_breakdown_qs = queryset.values('user', 'work_date', 'user__full_name', 'user__username').annotate(
#         # Sum all hours for this user on this date (and for the filtered project, if applicable)
#         total_daily_hours=Coalesce(Sum('hours'), Decimal('0.00')),
#         # Calculate overtime/under-time (Total Hours - 8h Standard)
#         overtime_hours=F('total_daily_hours') - HOURS_PER_DAY,
#         # Count unique projects logged on this day by this user (if project filter is not applied)
#         project_count=Count('project', distinct=True)
#     ).order_by('-work_date', 'user__full_name')

#     # 5. Total Summaries for Filtered Data
#     total_hours_sum = daily_breakdown_qs.aggregate(Sum('total_daily_hours'))['total_daily_hours__sum'] or Decimal('0.00')
#     total_overtime_sum = daily_breakdown_qs.aggregate(Sum('overtime_hours'))['overtime_hours__sum'] or Decimal('0.00')
    
#     # Total standard capacity is simply the number of daily entries * HOURS_PER_DAY
#     total_daily_entries = daily_breakdown_qs.count()
#     total_standard_sum = total_daily_entries * HOURS_PER_DAY
    
#     # 6. Pagination
#     paginator = Paginator(daily_breakdown_qs, 20)
#     page_number = request.GET.get('page')
#     page_obj = paginator.get_page(page_number)
    
#     # 7. Context Data
#     # Fetch all users/projects for the filter dropdowns
#     all_users = CustomUser.objects.order_by('full_name', 'username').all()
#     all_projects = Project.objects.order_by('name').all()
    
#     context = {
#         'page_obj': page_obj,
#         'total_hours_sum': total_hours_sum,
#         'total_overtime_sum': total_overtime_sum,
#         'total_standard_sum': total_standard_sum,
#         'standard_day_hours': HOURS_PER_DAY,
#         'all_users': all_users,
#         'all_projects': all_projects,
#         'project_pk': project_pk, # Used to toggle the "Total Projects Logged" column
#     }
    
#     return render(request, 'man_days_utilization_report.html', context)


@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def download_sqlite(request):
    db_path = settings.DATABASES['default']['NAME']  
    
    if not os.path.exists(db_path):
        raise Http404("Database file not found.")
    
    response = FileResponse(open(db_path, 'rb'))
    response['Content-Disposition'] = f'attachment; filename="{os.path.basename(db_path)}"'
    return response


from datetime import datetime, time

def parse_time(value):
    """
    Accepts:
    - datetime
    - time
    - string like: 10:00 AM, 2:30 PM, 14:00
    """
    if not value:
        return None

    if isinstance(value, time):
        return value

    if isinstance(value, datetime):
        return value.time()

    if isinstance(value, str):
        value = value.strip()
        for fmt in ("%I:%M %p", "%H:%M"):
            try:
                return datetime.strptime(value, fmt).time()
            except ValueError:
                continue

    raise ValueError(f"Invalid time format: '{value}'")



# @login_required
# def timesheet_bulk_upload(request):
#     # Ensure this endpoint is only accessible via POST
#     if request.method != 'POST':
#         messages.error(request, "Invalid request method.")
#         return redirect('home') 

#     if 'bulk_file' not in request.FILES:
#         messages.error(request, "No file was uploaded.")
#         return redirect('home')

#     excel_or_csv_file = request.FILES['bulk_file']
#     file_name = excel_or_csv_file.name.lower()

#     # 1. Updated File Validation
#     if not file_name.endswith(('.xlsx', '.xls', '.csv')):
#         messages.error(request, "Invalid file format. Please upload an Excel (.xlsx/.xls) or CSV (.csv) file.")
#         return redirect('home')

#     is_csv = file_name.endswith('.csv')
    
#     # Define allowed projects for the user (same logic as create view)
#     user_projects_query = Q(created_by=request.user)
#     public_projects_query = Q(is_public=True)
#     allowed_projects = models.Project.objects.filter(
#         Q(is_active=True), user_projects_query | public_projects_query
#     ).distinct().in_bulk(field_name='name') # Use project name as key for quick lookup
    
#     # Track results
#     success_count = 0
#     error_count = 0
#     error_messages = []
    
#     # --- Define expected column names for mapping (Case-insensitive matching) ---
#     col_map = {
#         'date': -1,
#         'project_name': -1,
#         'hours': -1,
#         'task_description': -1,
#         'task_type': -1,
#         'time_start': -1,
#         'time_end': -1 
#     }
#     required_cols = ['date', 'project_name', 'hours']

#     try:
#         data_rows = []
        
#         # --- File Parsing Logic (CSV vs. Excel) ---
#         if is_csv:
#             # Read CSV file
#             # Decode the file to a string, necessary for the csv reader
#             file_data = excel_or_csv_file.read().decode('utf-8').splitlines()
#             csv_reader = csv.reader(file_data)
            
#             # Get header and map columns
#             header = [h.strip() for h in next(csv_reader)]
            
#             for i, col_name in enumerate(header):
#                 if col_name and col_name.lower().replace(' ', '_') in col_map: # Handle spaces in CSV headers
#                     col_map[col_name.lower().replace(' ', '_')] = i
            
#             # Store data rows
#             data_rows = list(csv_reader)

#         else: # Excel (.xlsx or .xls)
#             # Load the workbook from the file data in memory
#             workbook = openpyxl.load_workbook(io.BytesIO(excel_or_csv_file.read()))
#             sheet = workbook.active
            
#             # Get header and map columns
#             header = [cell.value for cell in sheet[1]]
#             for i, col_name in enumerate(header):
#                 if col_name and col_name.lower() in col_map:
#                     col_map[col_name.lower()] = i
            
#             # Store data rows (skipping header)
#             data_rows = list(sheet.iter_rows(min_row=2, values_only=True))
        
#         # --- End File Parsing Logic ---

#         # Check if all critical columns are found regardless of file type
#         if any(col_map[c] == -1 for c in required_cols):
#              missing = [c for c in required_cols if col_map[c] == -1]
#              messages.error(request, f"Missing required columns in the file: {', '.join(missing)}. Please check your template.")
#              return redirect('home')

#         # Use a transaction to ensure atomicity (all or nothing for the batch)
#         with transaction.atomic():
            
#             # Iterate through the standardized list of data rows
#             for row_index, row in enumerate(data_rows, start=2): # Start index at 2 for user row visibility
                
#                 # Skip entirely empty rows
#                 if not any(row):
#                     continue

#                 try:
#                     # Extract data using the mapped indices
#                     date_val = row[col_map['date']]
#                     project_name = str(row[col_map['project_name']]).strip()
#                     hours_val = row[col_map['hours']]
#                     description = row[col_map['task_description']]
#                     task_type = row[col_map['task_type']] or 'Other'
#                     time_start_val = row[col_map['time_start']] if col_map['time_start'] != -1 else None
#                     time_end_val = row[col_map['time_end']] if col_map['time_end'] != -1 else None

#                     time_start = parse_time(time_start_val)
#                     time_end = parse_time(time_end_val)
#                     if time_start and time_end and time_end <= time_start:
#                         raise ValueError("time_end must be after time_start")  
#                     # 2. Convert Data Types
#                     work_date = None
#                     if isinstance(date_val, datetime):
#                         work_date = date_val.date()
#                     elif isinstance(date_val, str):
#                         # Handle potential different string date formats (e.g., from CSV)
#                         try:
#                             # Try YYYY-MM-DD
#                             work_date = datetime.strptime(date_val, '%Y-%m-%d').date()
#                         except ValueError:
#                             # Try common US format (e.g., 12/08/2025)
#                             work_date = datetime.strptime(date_val, '%m/%d/%Y').date()
                    
#                     if not work_date:
#                         raise ValueError(f"Invalid or empty date format: '{date_val}'")
                        
#                     hours = float(hours_val)
                    
#                     # 3. Validation Logic
#                     if hours <= 0:
#                         raise ValueError("Hours must be greater than zero.")
                    
#                     # Check Project existence and permission using the bulk map
#                     project = allowed_projects.get(project_name)
#                     if not project:
#                         raise models.Project.DoesNotExist(f"Project '{project_name}' not found or you lack permission.")
                        
#                     # 4. Create or Get Timesheet (Daily Grouping)
#                     timesheet, _ = models.Timesheet.objects.get_or_create(
#                         user=request.user, 
#                         date=work_date
#                     )
                    
#                     # 5. Create Timesheet Entry
#                     models.TimesheetEntry.objects.create(
#                             user=request.user,
#                             project=project,
#                             work_date=work_date,
#                             task_description=description or f"Bulk uploaded task for {project_name}",
#                             hours=hours,
#                             task_type=task_type,
#                             status='Inprogress',
#                             time_sheet=timesheet,
#                             time_start=time_start,
#                             time_end=time_end
#                         )
#                     success_count += 1
                    
#                 except Exception as e:
#                     error_count += 1
#                     error_messages.append(f"Row {row_index}: Error processing entry: {e}")
                    
#         # 6. Final Messages
#         if success_count > 0:
#             messages.success(request, f"Bulk upload completed! {success_count} entries were saved successfully.")
        
#         if error_count > 0:
#             error_summary = "\n".join(error_messages[:5])
#             messages.warning(request, f"{error_count} entries failed to process during bulk upload. Showing first 5 errors:\n{error_summary}")
            
#         return redirect('home')

#     except Exception as e:
#         messages.error(request, f"A critical error occurred while reading the file structure: {e}")
#         return redirect('home')
    
import csv
import io
import openpyxl
from datetime import datetime
from django.shortcuts import redirect
from django.contrib import messages
from django.db import transaction


from django.db.models import Q
from django.contrib.auth.decorators import login_required
@login_required
def timesheet_bulk_upload(request):
    if request.method != 'POST':
        messages.error(request, "Invalid request method.")
        return redirect('home') 

    if 'bulk_file' not in request.FILES:
        messages.error(request, "No file was uploaded.")
        return redirect('home')

    excel_or_csv_file = request.FILES['bulk_file']
    file_name = excel_or_csv_file.name.lower()

    if not file_name.endswith(('.xlsx', '.xls', '.csv')):
        messages.error(request, "Invalid file format. Please upload an Excel (.xlsx/.xls) or CSV (.csv) file.")
        return redirect('home')

    is_csv = file_name.endswith('.csv')
    
    user_projects_query = Q(created_by=request.user)
    public_projects_query = Q(is_public=True)
    allowed_projects = models.Project.objects.filter(
        Q(is_active=True), user_projects_query | public_projects_query
    ).distinct().in_bulk(field_name='name') 
    
    # 1. Updated mapping to include new fields
    col_map = {
        'date': -1,
        'project_name': -1,
        'hours': -1,
        'task_description': -1,
        'task_type': -1,
        'time_start': -1,
        'time_end': -1,
        'onsite_abroad': -1,  # New Field
        'onsite_egypt': -1    # New Field
    }
    required_cols = ['date', 'project_name', 'hours']

    try:
        data_rows = []
        if is_csv:
            file_data = excel_or_csv_file.read().decode('utf-8').splitlines()
            csv_reader = csv.reader(file_data)
            header = [h.strip().lower().replace(' ', '_') for h in next(csv_reader)]
            
            for i, col_name in enumerate(header):
                if col_name in col_map:
                    col_map[col_name] = i
            data_rows = list(csv_reader)
        else:
            workbook = openpyxl.load_workbook(io.BytesIO(excel_or_csv_file.read()))
            sheet = workbook.active
            header = [str(cell.value).strip().lower().replace(' ', '_') if cell.value else "" for cell in sheet[1]]
            
            for i, col_name in enumerate(header):
                if col_name in col_map:
                    col_map[col_name] = i
            data_rows = list(sheet.iter_rows(min_row=2, values_only=True))

        if any(col_map[c] == -1 for c in required_cols):
            missing = [c for c in required_cols if col_map[c] == -1]
            messages.error(request, f"Missing required columns: {', '.join(missing)}")
            return redirect('home')

        # Helper function to convert spreadsheet values to Boolean
        def clean_bool(val):
            if val is None: return False
            str_val = str(val).strip().lower()
            return str_val in ['true', '1', 'yes', 'y', 'checked']

        with transaction.atomic():
            success_count = 0
            for row_index, row in enumerate(data_rows, start=2):
                if not any(row): continue

                # Extraction
                date_val = row[col_map['date']]
                project_name = str(row[col_map['project_name']] or "").strip()
                hours_val = row[col_map['hours']]
                description = row[col_map['task_description']] if col_map['task_description'] != -1 else ""
                task_type = row[col_map['task_type']] if col_map['task_type'] != -1 else 'Other'
                
                # 2. Extract and clean the new boolean fields
                abroad_val = row[col_map['onsite_abroad']] if col_map['onsite_abroad'] != -1 else False
                egypt_val = row[col_map['onsite_egypt']] if col_map['onsite_egypt'] != -1 else False
                
                onsite_abroad = clean_bool(abroad_val)
                onsite_egypt = clean_bool(egypt_val)

                # Time Parsing
                time_start_val = row[col_map['time_start']] if col_map['time_start'] != -1 else None
                time_end_val = row[col_map['time_end']] if col_map['time_end'] != -1 else None
                time_start = parse_time(time_start_val)
                time_end = parse_time(time_end_val)

                if time_start and time_end and time_end <= time_start:
                    raise ValueError(f"Row {row_index}: End time must be after start time.")

                # Date Parsing
                work_date = None
                if isinstance(date_val, datetime):
                    work_date = date_val.date()
                elif isinstance(date_val, str):
                    for fmt in ('%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y'):
                        try:
                            work_date = datetime.strptime(date_val.strip(), fmt).date()
                            break
                        except ValueError: continue
                
                if not work_date:
                    raise ValueError(f"Row {row_index}: Invalid date format '{date_val}'.")

                # Validation
                try:
                    hours = float(hours_val)
                    if hours <= 0: raise ValueError
                except (TypeError, ValueError):
                    raise ValueError(f"Row {row_index}: Hours must be a positive number.")

                project = allowed_projects.get(project_name)
                if not project:
                    raise ValueError(f"Row {row_index}: Project '{project_name}' not found or restricted.")

                # Database Operations
                timesheet, _ = models.Timesheet.objects.get_or_create(
                    user=request.user, 
                    date=work_date
                )

                # 3. Create entry with new fields
                models.TimesheetEntry.objects.create(
                    user=request.user,
                    project=project,
                    work_date=work_date,
                    task_description=description or f"Bulk uploaded task for {project_name}",
                    hours=hours,
                    task_type=task_type,
                    status='Inprogress',
                    time_sheet=timesheet,
                    time_start=time_start,
                    time_end=time_end,
                    onsite_abroad=onsite_abroad, # Added
                    onsite_Egypt=onsite_egypt    # Added
                )
                success_count += 1

        messages.success(request, f"Successfully uploaded {success_count} entries.")

    except Exception as e:
        messages.error(request, f"Upload Failed: No data was saved. Error: {e}")
    
    return redirect('home')

# def export_man_days_pdf(request):
#     # Base Query
#     queryset = models.TimesheetEntry.objects.filter(is_scheduled=False).select_related('project', 'user')
    
#     # ... (Add your filtering logic here, e.g., queryset = queryset.filter(...)) ...

#     daily_stats = queryset.values(
#         'work_date', 'user__full_name', 'user__username', 'user__pk'
#     ).annotate(total_hours=Sum('hours')).order_by('-work_date')

#     refined_entries = []
#     total_h = 0
#     total_ot = 0
#     STANDARD = 8.0

#     for day in daily_stats:
#         day_tasks = queryset.filter(work_date=day['work_date'], user__pk=day['user__pk'])
        
#         # Check if ANY entry for this user on this day is onsite
#         is_abroad = day_tasks.filter(onsite_abroad=True).exists()
#         is_egypt = day_tasks.filter(onsite_Egypt=True).exists()
        
#         project_names = list(day_tasks.values_list('project__name', flat=True).distinct())
#         ot_val = get_post_5pm_overtime(day_tasks)
#         logged = float(day['total_hours'] or 0)
        
#         refined_entries.append({
#             'date': day['work_date'],
#             'employee_name': day['user__full_name'] or day['user__username'],
#             'logged_hours': logged,
#             'projects': project_names,
#             'ot_hours': ot_val,
#             'onsite_abroad': is_abroad,
#             'onsite_egypt': is_egypt,
#             'is_under': logged < STANDARD,
#             'difference': logged - STANDARD,
#         })
#         total_h += logged
#         total_ot += ot_val

#     context = {
#         'entries': refined_entries,
#         'total_hours_sum': total_h,
#         'total_overtime_sum': total_ot,
#         'today': datetime.now().date(),
#     }

#     html_string = render_to_string('man_days_pdf_template.html', context)
#     # Using WeasyPrint or similar
#     from weasyprint import HTML 
#     html = HTML(string=html_string, base_url=request.build_absolute_uri())
    
#     response = HttpResponse(content_type='application/pdf')
#     response['Content-Disposition'] = 'attachment; filename="Man_Days_Report.pdf"'
#     response.write(html.write_pdf())
#     return response



from django.db.models import Sum, Count, Case, When, Value, CharField
from django.template.loader import render_to_string
from weasyprint import HTML
from datetime import date
import os
from django.conf import settings
import os
from datetime import datetime
from django.conf import settings
from django.db.models import Sum, Q
from django.http import HttpResponse
from django.template.loader import render_to_string
from django.contrib.auth.decorators import login_required
from weasyprint import HTML
from . import models  # Ensure this points to your models file

# @login_required
# def export_man_days_pdf(request):
#     # 1. Capture Filters
#     user_pk = request.GET.get('user_pk')
#     project_pk = request.GET.get('project_pk')
#     start_date = request.GET.get('start_date')
#     end_date = request.GET.get('end_date')

#     # 2. Base Query
#     queryset = models.TimesheetEntry.objects.filter(is_scheduled=False).exclude(task_type="study").select_related('project', 'user', )

#     if user_pk: queryset = queryset.filter(user__pk=user_pk)
#     if project_pk: queryset = queryset.filter(project__pk=project_pk)
#     if start_date: queryset = queryset.filter(work_date__gte=start_date)
#     if end_date: queryset = queryset.filter(work_date__lte=end_date)

#     # 3. Aggregation
#     daily_stats = queryset.values(
#         'work_date', 'user__full_name', 'user__username', 'user__pk'
#     ).annotate(
#         total_hours=Sum('hours'),
#         egypt_h=Sum('hours', filter=Q(onsite_Egypt=True)),
#         abroad_h=Sum('hours', filter=Q(onsite_abroad=True))
#     ).order_by('-work_date', 'user__full_name')

#     refined_entries = []
#     totals = {'hours': 0.0, 'ot': 0.0, 'egypt': 0.0, 'abroad': 0.0}

#     for day in daily_stats:
#         # Task breakdown for OT and Project list
#         day_tasks = queryset.filter(work_date=day['work_date'], user__pk=day['user__pk'])
        
#         # Calculate OT (External helper function assumed)
#         ot_val = float(get_post_5pm_overtime(day_tasks)) 
#         logged = float(day['total_hours'] or 0)
        
#         # Project Breakdown per day
#         project_details = day_tasks.values('project__name').annotate(p_hours=Sum('hours'))

#         refined_entries.append({
#             'date': day['work_date'],
#             'employee_name': day['user__full_name'] or day['user__username'],
#             'projects': project_details,
#             'logged_hours': logged,
#             'ot_hours': ot_val,
#             'egypt_hours': float(day['egypt_h'] or 0),
#             'abroad_hours': float(day['abroad_h'] or 0),
#         })
        
#         totals['hours'] += logged
#         totals['ot'] += ot_val
#         totals['egypt'] += float(day['egypt_h'] or 0)
#         totals['abroad'] += float(day['abroad_h'] or 0)

#     server_url = request.build_absolute_uri('/')
#     print(server_url)
#     context = {
#         'entries': refined_entries,
#         'totals': totals,
#         'today': datetime.now(),
#         'server_url': server_url.rstrip('/'),
#     }

#     html_string = render_to_string('man_days_pdf_template.html', context)
    
#     # Passing the request's absolute URI as base_url helps resolve paths
#     html = HTML(string=html_string, base_url=request.build_absolute_uri())
    
#     response = HttpResponse(content_type='application/pdf')
#     # Use 'filename' to suggest a name; browser default is usually the first page
#     response['Content-Disposition'] = f'attachment; filename="Man_Days_Report_{datetime.now().strftime("%Y%m%d")}.pdf"'
#     response.write(html.write_pdf())
#     return response


@login_required
def export_man_days_pdf(request):
    # 1. Capture Filters
    user_pk = request.GET.get('user_pk')
    project_pk = request.GET.get('project_pk')
    start_date = request.GET.get('start_date')
    end_date = request.GET.get('end_date')
    work_location = request.GET.get('work_location')  # New Filter Parameter

    # 2. Base Query
    queryset = models.TimesheetEntry.objects.filter(
        is_scheduled=False
    ).exclude(task_type="study").select_related('project', 'user')

    # Apply existing filters
    if user_pk: queryset = queryset.filter(user__pk=user_pk)
    if project_pk: queryset = queryset.filter(project__pk=project_pk)
    if start_date: queryset = queryset.filter(work_date__gte=start_date)
    if end_date: queryset = queryset.filter(work_date__lte=end_date)

    # NEW: Apply Task Type (Location) Filter logic
    if work_location == 'abroad':
        queryset = queryset.filter(onsite_abroad=True)
    elif work_location == 'remote':
        queryset = queryset.filter(onsite_abroad=False)

    # 3. Aggregation (Will now respect the work_location filter applied above)
    daily_stats = queryset.values(
        'work_date', 'user__full_name', 'user__username', 'user__pk'
    ).annotate(
        total_hours=Sum('hours'),
        egypt_h=Sum('hours', filter=Q(onsite_Egypt=True)),
        abroad_h=Sum('hours', filter=Q(onsite_abroad=True))
    ).order_by('-work_date', 'user__full_name')

    refined_entries = []
    totals = {'hours': 0.0, 'ot': 0.0, 'egypt': 0.0, 'abroad': 0.0}

    for day in daily_stats:
        # Task breakdown for OT and Project list (Inherits the location filter)
        day_tasks = queryset.filter(work_date=day['work_date'], user__pk=day['user__pk'])
        
        # Calculate OT (External helper function)
        ot_val = float(get_post_5pm_overtime(day_tasks)) 
        logged = float(day['total_hours'] or 0)
        
        # Project Breakdown per day
        project_details = day_tasks.values('project__name').annotate(p_hours=Sum('hours'))

        refined_entries.append({
            'date': day['work_date'],
            'employee_name': day['user__full_name'] or day['user__username'],
            'projects': project_details,
            'logged_hours': logged,
            'ot_hours': ot_val,
            'egypt_hours': float(day['egypt_h'] or 0),
            'abroad_hours': float(day['abroad_h'] or 0),
        })
        
        totals['hours'] += logged
        totals['ot'] += ot_val
        totals['egypt'] += float(day['egypt_h'] or 0)
        totals['abroad'] += float(day['abroad_h'] or 0)

    server_url = request.build_absolute_uri('/')
    context = {
        'entries': refined_entries,
        'totals': totals,
        'today': datetime.now(),
        'server_url': server_url.rstrip('/'),
        'applied_filter': work_location, # Useful if you want to display the filter type in the PDF header
    }

    html_string = render_to_string('man_days_pdf_template.html', context)
    
    # Generate PDF
    html = HTML(string=html_string, base_url=request.build_absolute_uri())
    
    response = HttpResponse(content_type='application/pdf')
    response['Content-Disposition'] = f'attachment; filename="Man_Days_Report_{datetime.now().strftime("%Y%m%d")}.pdf"'
    response.write(html.write_pdf())
    return response


@user_passes_test(lambda u: is_admin(u) or is_manager(u) or is_leader(u), login_url=reverse_lazy('home'))
def assignement_create(request):
    if request.method == "POST":
        data = request.POST
        try:
            assignment =Assignement.objects.create(employee=CustomUser.objects.get(id=data.get("employee")),
                                       body=data.get("body"),
                                       status="Pending",
                                       created_by=request.user,
                                       priority=data.get("priority"),
                                       deadline=data.get("deadline")
                                       )
            if data.get("project"):
                assignment.project=Project.objects.get(id=data.get("project")),
                assignment.save()
            subject = f"🚀 New Mission Assigned: {assignment.project.name if assignment.project else 'General Task'}"

            accept_url = request.build_absolute_uri(
                reverse('accept_mission', kwargs={'pk': assignment.pk})
            )

            html_message = render_to_string('mission_notification.html', {
                'employee': assignment.employee.full_name,
                'project': assignment.project.name if assignment.project else 'General',
                'priority': assignment.priority,
                'deadline': assignment.deadline,
                'body': assignment.body,
                'accept_url': accept_url,          
            })

            send_mail(
                subject,
                "", 
                settings.DEFAULT_FROM_EMAIL,
                [assignment.employee.email],
                html_message=html_message,
                fail_silently=False,
            )
            
            messages.success(request, "The Assignement Created Successfully..")
            return redirect('assign_task')

        except Exception as e:
            messages.warning(request, f'there is an Error Occured {e}')
    return render(request, 'assignment_create.html', {
        "employees": CustomUser.objects.all(),
        "projects": Project.objects.all(),
        "recent_assignments": Assignement.objects.all().order_by('-created_at')[:5]
    })

from django.contrib.auth import get_user_model
User = get_user_model()

def company_profile(request):
    return render(request, 'company_profile.html', {
    })

from django.shortcuts import render
from django.contrib.auth.decorators import login_required
from django.core.paginator import Paginator
from django.utils import timezone
from .models import Assignement, CustomUser, Project 

@login_required
def missions_list(request):
    if request.method == "POST":
        data = request.POST
        try:
            assignment =Assignement.objects.create(employee=CustomUser.objects.get(id=data.get("employee")),
                                       body=data.get("body"),
                                       status="Pending",
                                       created_by=request.user,
                                       priority=data.get("priority"),
                                       deadline=data.get("deadline")
                                       )
            subject = f"🚀 New Mission Assigned: {assignment.project.name if assignment.project else 'General Task'}"
            if data.get("project"):
                assignment.project=Project.objects.get(id=data.get("project")),
                assignment.save()
            
            accept_url = request.build_absolute_uri(
                reverse('accept_mission', kwargs={'pk': assignment.pk})
            )

            html_message = render_to_string('mission_notification.html', {
                'employee': assignment.employee.full_name,
                'project': assignment.project.name if assignment.project else 'General',
                'priority': assignment.priority,
                'deadline': assignment.deadline,
                'body': assignment.body,
                'accept_url': accept_url,          
            })

            send_mail(
                subject,
                "", 
                settings.DEFAULT_FROM_EMAIL,
                [assignment.employee.email],
                html_message=html_message,
                fail_silently=False,
            )
            
            messages.success(request, "The Assignement Created Successfully..")
            return redirect('missions_list')

        except Exception as e:
            messages.warning(request, f'there is an Error Occured {e}')
            return redirect("missions_list")
         
    user = request.user
    if is_admin(user) or is_top_manager(user):
        employees = CustomUser.objects.all()
    elif is_leader(user):
        employees = CustomUser.objects.filter(team__team_lead=user.full_name)
    else:
        employees = None

    selected_employee_id = request.GET.get('employee')

    created_qs = Assignement.objects.filter(created_by=user).order_by('-deadline')
    assigned_qs = Assignement.objects.filter(employee=user).order_by('-deadline')

    if selected_employee_id:
        created_qs = created_qs.filter(employee_id=selected_employee_id)

    paginator_created = Paginator(created_qs, 10) 
    paginator_assigned = Paginator(assigned_qs, 10)

    page_created = request.GET.get('p_created')
    page_assigned = request.GET.get('p_assigned')

    created_page_obj = paginator_created.get_page(page_created)
    assigned_page_obj = paginator_assigned.get_page(page_assigned)

    return render(request, 'missions_list.html', {
        "employees": employees,
        "created_tasks_by_me": created_page_obj,
        "assigned_tasks_to_me": assigned_page_obj,
        "projects": Project.objects.all(),
        "now": timezone.now(),
    })

@login_required
def send_mission_reminder(request, task_id):
    """Sends a reminder email for overdue missions."""
    task = get_object_or_404(Assignement, id=task_id, created_by=request.user)
    
    subject = f"🚨 URGENT: Mission Overdue - {task.body[:30]}..."
    message = f"Hello {task.employee.username},\n\nYour mission is currently OVERDUE.\n\nTask: {task.body}\nDeadline: {task.deadline.strftime('%Y-%m-%d %H:%M')}\n\nPlease update the status immediately."
    
    try:
        send_mail(subject, message, settings.DEFAULT_FROM_EMAIL, [task.employee.email])
        messages.success(request, f"Reminder signal sent to {task.employee.username}!")
    except Exception:
        messages.error(request, "Failed to send email. Check SMTP settings.")
        
    return redirect('missions_list')

@login_required
def update_task_status(request, task_id):
    user = request.user

# # In views.py (use Django generic views for CRUD)
# from django.views.generic import ListView, CreateView, UpdateView, DeleteView, DetailView
# from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
# from django.shortcuts import get_object_or_404, redirect
# from django.db.models import Sum
# from .models import KPITemplate, EmployeeKPI, KPIFeedback, CustomUser
# from .forms import KPITemplateForm, EmployeeKPIFormSet

# # Admin check mixin
# class AdminRequiredMixin(UserPassesTestMixin):
#     def test_func(self):
#         return self.request.user.is_staff  # Assuming staff are admins as per your CustomUser save method

# from django.contrib.auth.mixins import UserPassesTestMixin
# from django.core.exceptions import PermissionDenied

# class ManagementRequiredMixin(UserPassesTestMixin):
#     """
#     Allows access only to Admins, Delivery Managers, Top Managers, or CEOs.
#     """
#     def test_func(self):
#         user = self.request.user
#         is_admin = user.is_superuser or user.role == "admin"
#         is_manager = user.role in ["delivery-manager", "top-manager", "ceo", "leader"]
        
#         return user.is_authenticated and (is_admin or is_manager)

#     def handle_no_permission(self):
#         if self.request.user.is_authenticated:
#             raise PermissionDenied  # Shows 403 Forbidden
#         return super().handle_no_permission()

# # KPI Template Views
# from django.views.generic import ListView
# from .models import KPITemplate, KPICategory

# class KPITemplateListView(LoginRequiredMixin, ManagementRequiredMixin, ListView):
#     model = KPITemplate
#     template_name = 'kpi/template_list.html'
#     context_object_name = 'object_list'   # optional, but explicit is good
#     paginate_by = 20   # optional: add pagination if you have many templates

#     def get_queryset(self):
#         queryset = super().get_queryset()

#         category_id = self.request.GET.get('category')
#         source = self.request.GET.get('source')

#         if category_id:
#             queryset = queryset.filter(category_id=category_id)

#         if source:
#             queryset = queryset.filter(source=source)

#         return queryset

#     def get_context_data(self, **kwargs):
#         context = super().get_context_data(**kwargs)

#         # Pass all categories and sources for the filter dropdowns
#         context['categories'] = KPICategory.objects.all().order_by('name')
#         context['sources'] = KPITemplate.SOURCE  # the choices tuple

#         # Preserve current filter values in the form (for selected="selected")
#         context['selected_category'] = self.request.GET.get('category', '')
#         context['selected_source'] = self.request.GET.get('source', '')

#         return context

        
# from django.views.generic import CreateView
# from django.contrib.auth.mixins import LoginRequiredMixin
# from .models import KPITemplate, KPICategory
# from .forms import KPITemplateForm
# from django.http import JsonResponse
# from .models import KPICategory

# def ajax_create_category(request):
#     if request.method == 'POST':
#         name = request.POST.get('name', '').strip()
#         if name:
#             category, created = KPICategory.objects.get_or_create(name=name)
#             return JsonResponse({'id': category.id, 'name': category.name})
#     return JsonResponse({'error': 'Invalid request'}, status=400)

# class KPITemplateCreateView(LoginRequiredMixin, ManagementRequiredMixin, CreateView):
#     model = KPITemplate
#     form_class = KPITemplateForm
#     template_name = 'kpi/template_form.html'
#     success_url = '/kpi/templates/'


# class KPITemplateUpdateView(LoginRequiredMixin, ManagementRequiredMixin, UpdateView):
#     model = KPITemplate
#     form_class = KPITemplateForm
#     template_name = 'kpi/template_form.html'
#     success_url = '/kpi/templates/'

# class KPITemplateDeleteView(LoginRequiredMixin, ManagementRequiredMixin, DeleteView):
#     model = KPITemplate
#     template_name = 'kpi/template_confirm_delete.html'  # HTML: Confirm delete
#     success_url = '/kpi/templates/'

    
# class EmployeeKPIListView(LoginRequiredMixin, ManagementRequiredMixin, ListView):
#     model = CustomUser
#     template_name = 'kpi/employee_list.html'
#     paginate_by = 10

#     def get_queryset(self):
#         queryset = super().get_queryset()
#         if self.request.user.role == "leader":
#             queryset = queryset.filter(team__team_lead=self.request.user.full_name).exclude(username=self.request.user.username)
#         search_query = self.request.GET.get('search', '')
#         if search_query:
#             # Filters by username OR full_name (case-insensitive)
#             queryset = queryset.filter(
#                 Q(username__icontains=search_query) | 
#                 Q(full_name__icontains=search_query)
#             )
#         return queryset

#     def get_context_data(self, **kwargs):
#         context = super().get_context_data(**kwargs)
#         context["current_year"] = datetime.now().year
#         context["current_month"] = datetime.now().month
#         context['all_employees'] = self.get_queryset().filter(username__in=['abd.mon.sh', 'afarouk', 'semad',  'amustafa']).order_by('full_name')
#         return context

# from django.views.generic import View

# class KPIReportPDFView(LoginRequiredMixin, ManagementRequiredMixin, View):
#     def get(self, request, *args, **kwargs):
#         year = int(request.GET.get('year', datetime.now().year))
#         month = int(request.GET.get('month', datetime.now().month))
#         month_name = datetime(year, month, 1).strftime('%B')

#         # Aggregate total score per employee for the selected period
#         employees = CustomUser.objects.filter(
#             kpis__year=year,
#             kpis__month=month
#         ).distinct().annotate(
#             total_score=Sum('kpis__score')
#         ).order_by('full_name')

#         context = {
#             'year': year,
#             'month_name': month_name,
#             'report_date': datetime.now(),
#             'employees': [
#                 {
#                     'full_name': emp.full_name or emp.username,
#                     'username': emp.username,
#                     'total_score': round(emp.total_score,2) or 0
#                 } for emp in employees if emp.username not in ['semad', 'm.mohamed']
#             ]
#         }

#         html_string = render_to_string('kpi/admin_kpi_report.html', context)
#         pdf = HTML(string=html_string).write_pdf()

#         response = HttpResponse(pdf, content_type='application/pdf')
#         response['Content-Disposition'] = f'Inline; filename="KPI_Report_{month_name}_{year}.pdf"'
#         return response

# # views.py
# from django.shortcuts import redirect
# from django.contrib import messages
# from django.core.mail import EmailMessage
# from django.conf import settings
# from django.views import View
# from django.template.loader import render_to_string
# from django.db.models import Sum
# from datetime import datetime

# # views.py
# from django.shortcuts import redirect
# from django.contrib import messages
# from django.core.mail import EmailMessage
# from django.conf import settings
# from django.views import View
# from django.template.loader import render_to_string
# from django.db.models import Sum
# from datetime import datetime


# class SendKPIReportEmailView(LoginRequiredMixin, ManagementRequiredMixin, View):
#     """
#     Sends KPI Report PDF + nice HTML email to selected employees.
#     """
#     def post(self, request, *args, **kwargs):
#         year = int(request.POST.get('year', datetime.now().year))
#         month = int(request.POST.get('month', datetime.now().month))
#         employee_ids = request.POST.getlist('employees')   # list of PKs from modal

#         if not employee_ids:
#             messages.warning(request, "No employees were selected. Please select at least one employee.")
#             return redirect('employee_kpi_list')

#         # Get selected employees
#         selected_employees = CustomUser.objects.filter(pk__in=employee_ids).only(
#             'pk', 'full_name', 'username', 'email'
#         )

#         month_name = datetime(year, month, 1).strftime('%B')

#         # === Build report data (same as your PDF view) ===
#         employees_for_report = CustomUser.objects.filter(
#             kpis__year=year,
#             kpis__month=month
#         ).distinct().annotate(
#             total_score=Sum('kpis__score')
#         ).order_by('full_name')

#         report_context = {
#             'year': year,
#             'month_name': month_name,
#             'report_date': datetime.now(),
#             'employees': [
#                 {
#                     'full_name': emp.full_name or emp.username,
#                     'username': emp.username,
#                     'total_score': round(emp.total_score or 0, 2)
#                 }
#                 for emp in employees_for_report
#                 if emp.username not in ['semad', 'm.mohamed']
#             ]
#         }

#         # Generate PDF once (same as KPIReportPDFView)
#         html_string = render_to_string('kpi/admin_kpi_report.html', report_context)
#         pdf_bytes = HTML(string=html_string).write_pdf()

#         # === Send emails ===
#         subject = f"KPI Report - {month_name} {year}"
#         sent_count = 0
#         skipped_count = 0

#         for employee in selected_employees:
#             if not employee.email:
#                 skipped_count += 1
#                 continue

#             # Personalized email context
#             email_context = {
#                 'employee': employee,
#                 'year': year,
#                 'month_name': month_name,
#                 'report_date': datetime.now(),
#                 'total_employees_in_report': len(report_context['employees']),
#             }

#             html_body = render_to_string('kpi/send_kpi_report_to_manager.html', email_context)

#             email = EmailMessage(
#                 subject=subject,
#                 body=html_body,
#                 from_email=settings.DEFAULT_FROM_EMAIL,
#                 to=[employee.email],
#             )
#             email.content_subtype = "html"

#             email.attach(
#                 filename=f"KPI_Report_{month_name}_{year}.pdf",
#                 content=pdf_bytes,
#                 mimetype='application/pdf'
#             )

#             try:
#                 email.send(fail_silently=False)
#                 sent_count += 1
#             except Exception as e:
#                 # In development you will see the error in console
#                 print(f"❌ Email failed for {employee.email}: {e}")
#                 skipped_count += 1

#         # === Better user feedback ===
#         if sent_count > 0:
#             messages.success(
#                 request,
#                 f"✅ KPI Report for <strong>{month_name} {year}</strong> "
#                 f"was successfully sent to {sent_count} employee(s)."
#             )
#         elif skipped_count > 0:
#             messages.warning(
#                 request,
#                 f"⚠️ No emails were sent. {skipped_count} selected employee(s) "
#                 f"do not have an email address configured."
#             )
#         else:
#             messages.error(request, "❌ Something went wrong. No report was sent.")

#         return redirect('employee_kpi_list')
    
# class EmployeeKPIDetailView(LoginRequiredMixin, AdminRequiredMixin, DetailView):
#     model = CustomUser
#     template_name = 'kpi/employee_kpi_detail.html'
#     pk_url_kwarg = 'employee_id'

#     def dispatch(self, request, *args, **kwargs):
#         today = date.today()
#         self.year = kwargs.get('year', today.year)
#         self.month = kwargs.get('month', today.month)
#         return super().dispatch(request, *args, **kwargs)

#     def get_context_data(self, **kwargs):
#         context = super().get_context_data(**kwargs)
#         employee = self.object
        
#         # 1. Ensure records exist
#         if employee.team.title == "PMO":
#             templates = KPITemplate.objects.filter(Q(source="PMO"))
#         elif employee.role == "leader":
#             templates = KPITemplate.objects.filter(Q(source="General")|Q(source="Leader"))

#         else:
#             templates = KPITemplate.objects.filter(Q(source="General")|Q(source=employee.team.title))

        
#         for template in templates:
#             EmployeeKPI.objects.get_or_create(
#                 employee=employee,
#                 kpi_template=template,
#                 year=self.year,
#                 month=self.month,
#                 defaults={'grade': template.default_grade}
#             )
        
#         # 2. Fetch records ordered by category for a better UI
#         kpis = EmployeeKPI.objects.filter(employee=employee, year=self.year, month=self.month).select_related('kpi_template', 'kpi_template__category')
#         total_score = round(kpis.aggregate(Sum('score'))['score__sum'] or Decimal('0.00'), 2)
        
#         # 3. Formset setup
#         EmployeeKPIFormSet = modelformset_factory(EmployeeKPI, fields=('grade', 'notes'), extra=0)
        
#         # If we are returning from a failed POST, the formset is already in context
#         if 'formset' not in context:
#             context['formset'] = EmployeeKPIFormSet(queryset=kpis)
            
#         context['total_score'] = total_score
#         context['year'] = self.year
#         context['month'] = self.month
#         context['month_choices'] = self.get_month_choices()
#         return context
    
#     def get_month_choices(self):
#         today = date.today()
#         choices = []
#         for i in range(12):
#             y = today.year if today.month > i else today.year - 1
#             m = (today.month - i - 1) % 12 + 1
            
#             # We pass: (year_int, month_int, "year-month_string", "label_string")
#             choices.append((y, m, f"{y}-{m}", f"{y}-{m:02d}"))
#         return choices
    
#     def post(self, request, *args, **kwargs):
#         self.object = self.get_object()
#         employee = self.object
        
#         kpis = EmployeeKPI.objects.filter(
#             employee=employee, year=self.year, month=self.month
#         )
        
#         EmployeeKPIFormSet = modelformset_factory(EmployeeKPI, fields=('grade', 'notes'), extra=0)
#         formset = EmployeeKPIFormSet(request.POST, queryset=kpis)
        
#         if formset.is_valid():
#             formset.save()
#             messages.success(request, f"KPIs for {employee.full_name} ({self.year}-{self.month:02d}) have been updated successfully!")
#             return redirect('employee_kpi_detail', employee_id=employee.id, year=self.year, month=self.month)
#         else:
#             messages.error(request, "There was an error updating the grades. Please check the values.")
#             return self.render_to_response(self.get_context_data(formset=formset))
                


# class MyKPIView(LoginRequiredMixin, ListView):
#     template_name = 'kpi/my_kpi.html'  
    
#     def dispatch(self, request, *args, **kwargs):
#         today = date.today()
#         self.year = kwargs.get('year', today.year)
#         self.month = kwargs.get('month', today.month)
#         return super().dispatch(request, *args, **kwargs)
    
#     def get_queryset(self):
#         return EmployeeKPI.objects.filter(
#             employee=self.request.user, year=self.year, month=self.month
#         )
    
#     def get_context_data(self, **kwargs):
#         context = super().get_context_data(**kwargs)
#         total_score = round(self.get_queryset().aggregate(Sum('score'))['score__sum'] or Decimal('0.00'), 2)
#         context['total_score'] = total_score
#         context['year'] = self.year
#         context['month'] = self.month
#         # Add month choices similar to detail view
#         context['month_choices'] = self.get_month_choices()  # Reuse method if refactored
#         return context

#     def get_month_choices(self):
#         today = date.today()
#         choices = []
#         for i in range(12):
#             y = today.year if today.month > i else today.year - 1
#             m = (today.month - i - 1) % 12 + 1
            
#             # We pass: (year_int, month_int, "year-month_string", "label_string")
#             choices.append((y, m, f"{y}-{m}", f"{y}-{m:02d}"))
#         return choices
    
# # Feedback Create (for admins to log complaints/issues)
# class KPIFeedbackCreateView(LoginRequiredMixin, AdminRequiredMixin, CreateView):
#     model = KPIFeedback
#     fields = ['employee', 'kpi_template', 'feedback_type', 'description', 'date', 'value']
#     template_name = 'kpi/feedback_form.html'
#     success_url = '/kpi/employees/'  

# from django.template.loader import render_to_string
# from django.core.mail import EmailMultiAlternatives
# from django.utils.html import strip_tags
# from django.conf import settings
# from django.contrib import messages
# from django.shortcuts import get_object_or_404, redirect
# from .models import  EmployeeKPI

# def send_kpi_feedback(request, employee_id):
#     if request.method == "POST":
#         employee = get_object_or_404(CustomUser, id=employee_id) 
#         year = request.POST.get('year')
#         month = request.POST.get('month')
#         overall_notes = request.POST.get('message')
#         kpis = EmployeeKPI.objects.filter(
#             employee=employee, 
#             year=year, 
#             month=month
#         )

#         total_score = sum(kpi.score for kpi in kpis) if kpis.exists() else 0
        
#         if total_score >= 90: achievement_level = "Outstanding Performance"
#         elif total_score >= 80: achievement_level = "Excellent Achievement"
#         elif total_score >= 70: achievement_level = "Good Progress"
#         else: achievement_level = "Improvement Required"

#         # 4. Prepare Email Content
#         subject = f"🚀 Performance Report: {employee.full_name} ({month}/{year})"
        
#         context = {
#             'employee': employee,
#             'month': month,
#             'year': year,
#             'total_score': round(total_score, 1),
#             'achievement_level': achievement_level,
#             'overall_notes': overall_notes,
#             'kpis': kpis,
#             'logo_url': request.build_absolute_uri(settings.STATIC_URL + 'img/Smart-System-Logo.webp') # Ensure your logo path is correct
#         }

#         html_content = render_to_string('kpi/kpi_email_report.html', context)
#         text_content = strip_tags(html_content) 

#         # 5. Send Email
#         try:
#             email = EmailMultiAlternatives(
#                 subject,
#                 text_content,
#                 settings.DEFAULT_FROM_EMAIL,
#                 [employee.email]
#             )
#             email.attach_alternative(html_content, "text/html")
#             email.send()
            
#             messages.success(request, f"Report sent successfully to {employee.email}")
#         except Exception as e:
#             messages.error(request, f"Failed to send email: {str(e)}")

#     return redirect(request.META.get('HTTP_REFERER', 'employee_kpi_list'))


from django.views.generic import ListView, CreateView, UpdateView, DeleteView, DetailView, View
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.shortcuts import get_object_or_404, redirect
from django.db.models import Sum, Q
from django.http import JsonResponse, HttpResponse
from django.forms import modelformset_factory
from django.contrib import messages
from django.core.mail import EmailMessage, EmailMultiAlternatives
from django.template.loader import render_to_string
from django.utils.html import strip_tags
from django.conf import settings
from decimal import Decimal
from datetime import date, datetime

from .models import KPITemplate, EmployeeKPI, KPIFeedback, CustomUser, KPICategory
from .forms import KPITemplateForm

# واجهة Weasyprint لطباعة الـ PDF (تأكد من تثبيتها واستيرادها كما كنت تفعل)
# from weasyprint import HTML 

class AdminRequiredMixin(UserPassesTestMixin):
    def test_func(self):
        return self.request.user.is_staff

class ManagementRequiredMixin(UserPassesTestMixin):
    def test_func(self):
        user = self.request.user
        is_admin = user.is_superuser or user.role == "admin"
        is_manager = user.role in ["delivery-manager", "top-manager", "ceo", "leader"]
        return user.is_authenticated and (is_admin or is_manager)

    def handle_no_permission(self):
        from django.core.exceptions import PermissionDenied
        if self.request.user.is_authenticated:
            raise PermissionDenied
        return super().handle_no_permission()

# Helper function لمعرفة ربع السنة الحالي بناءً على تاريخ اليوم
def get_current_quarter_month():
    today = date.today()
    if today.month in [1, 2, 3]:
        return 3
    elif today.month in [4, 5, 6]:
        return 6
    elif today.month in [7, 8, 9]:
        return 9
    else:
        return 12

# Helper function لتحويل رقم الربع السنوي لاسم نصي واضح في التقارير
def get_quarter_label(qm):
    mapping = {3: "31/3 (Q1)", 6: "30/6 (Q2)", 9: "30/9 (Q3)", 12: "31/12 (Q4)"}
    return mapping.get(qm, f"Period {qm}")

# KPI Template Views
class KPITemplateListView(LoginRequiredMixin, ManagementRequiredMixin, ListView):
    model = KPITemplate
    template_name = 'kpi/template_list.html'
    context_object_name = 'object_list'
    paginate_by = 20

    def get_queryset(self):
        queryset = super().get_queryset()
        category_id = self.request.GET.get('category')
        source = self.request.GET.get('source')
        if category_id:
            queryset = queryset.filter(category_id=category_id)
        if source:
            queryset = queryset.filter(source=source)
        return queryset

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context['categories'] = KPICategory.objects.all().order_by('name')
        context['sources'] = KPITemplate.SOURCE
        context['selected_category'] = self.request.GET.get('category', '')
        context['selected_source'] = self.request.GET.get('source', '')
        return context

def ajax_create_category(request):
    if request.method == 'POST':
        name = request.POST.get('name', '').strip()
        if name:
            category, created = KPICategory.objects.get_or_create(name=name)
            return JsonResponse({'id': category.id, 'name': category.name})
    return JsonResponse({'error': 'Invalid request'}, status=400)

class KPITemplateCreateView(LoginRequiredMixin, ManagementRequiredMixin, CreateView):
    model = KPITemplate
    form_class = KPITemplateForm
    template_name = 'kpi/template_form.html'
    success_url = '/kpi/templates/'

class KPITemplateUpdateView(LoginRequiredMixin, ManagementRequiredMixin, UpdateView):
    model = KPITemplate
    form_class = KPITemplateForm
    template_name = 'kpi/template_form.html'
    success_url = '/kpi/templates/'

class KPITemplateDeleteView(LoginRequiredMixin, ManagementRequiredMixin, DeleteView):
    model = KPITemplate
    template_name = 'kpi/template_confirm_delete.html'
    success_url = '/kpi/templates/'

class EmployeeKPIListView(LoginRequiredMixin, ManagementRequiredMixin, ListView):
    model = CustomUser
    template_name = 'kpi/employee_list.html'
    paginate_by = 10

    def get_queryset(self):
        queryset = super().get_queryset()
        if self.request.user.role == "leader":
            queryset = queryset.filter(team__team_lead=self.request.user.full_name).exclude(username=self.request.user.username)
        search_query = self.request.GET.get('search', '')
        if search_query:
            queryset = queryset.filter(
                Q(username__icontains=search_query) | 
                Q(full_name__icontains=search_query)
            )
        return queryset

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context["current_year"] = date.today().year
        context["current_quarter_month"] = get_current_quarter_month()
        context['all_employees'] = self.get_queryset().filter(username__in=['abd.mon.sh', 'afarouk', 'semad', 'amustafa']).order_by('full_name')
        return context

class KPIReportPDFView(LoginRequiredMixin, ManagementRequiredMixin, View):
    def get(self, request, *args, **kwargs):
        year = int(request.GET.get('year', date.today().year))
        quarter_month = int(request.GET.get('quarter_month', get_current_quarter_month()))
        quarter_label = get_quarter_label(quarter_month)

        employees = CustomUser.objects.filter(
            kpis__year=year,
            kpis__quarter_month=quarter_month
        ).exclude(username__in=['Aziz', 'abd.mon.sh', 'afarouk', 'semad']).distinct().annotate(
            total_score=Sum('kpis__score')
        ).order_by('full_name')

        context = {
            'year': year,
            'quarter_label': quarter_label,
            'quarter_month': quarter_month,
            'report_date': datetime.now(),
            'employees': [
                {
                    'full_name': emp.full_name or emp.username,
                    'username': emp.username,
                    'total_score': round(emp.total_score, 2) if emp.total_score else 0
                } for emp in employees if emp.username not in ['semad', 'm.mohamed']
            ]
        }

        html_string = render_to_string('kpi/admin_kpi_report.html', context)
        pdf = HTML(string=html_string).write_pdf()
        response = HttpResponse(pdf, content_type='application/pdf')
        response['Content-Disposition'] = f'inline; filename="KPI_Report_{quarter_month}_{year}.pdf"'
        return response
       
class SendKPIReportEmailView(LoginRequiredMixin, ManagementRequiredMixin, View):
    def post(self, request, *args, **kwargs):
        year = int(request.POST.get('year', date.today().year))
        quarter_month = int(request.POST.get('quarter_month', get_current_quarter_month()))
        employee_ids = request.POST.getlist('employees')

        if not employee_ids:
            messages.warning(request, "No employees were selected. Please select at least one employee.")
            return redirect('employee_kpi_list')

        selected_employees = CustomUser.objects.filter(pk__in=employee_ids).only('pk', 'full_name', 'username', 'email')
        quarter_label = get_quarter_label(quarter_month)

        employees_for_report = CustomUser.objects.filter(
            kpis__year=year,
            kpis__quarter_month=quarter_month
        ).exclude(username__in=['Aziz', 'abd.mon.sh', 'afarouk', 'semad']).distinct().annotate(
            total_score=Sum('kpis__score')
        ).order_by('full_name')

        report_context = {
            'year': year,
            'quarter_label': quarter_label,
            'quarter_month': quarter_month,
            'report_date': datetime.now(),
            'employees': [
                {
                    'full_name': emp.full_name or emp.username,
                    'username': emp.username,
                    'total_score': round(emp.total_score or 0, 2)
                } for emp in employees_for_report if emp.username not in ['semad', 'm.mohamed']
            ]
        }

        html_string = render_to_string('kpi/admin_kpi_report.html', report_context)
        pdf_bytes = HTML(string=html_string).write_pdf() # فك التعليق عند استخدام weasyprint

        subject = f"KPI Report - Period Ending {quarter_label} {year}"
        sent_count = 0
        skipped_count = 0

        for employee in selected_employees:
            if not employee.email:
                skipped_count += 1
                continue

            email_context = {
                'employee': employee,
                'year': year,
                'quarter_label': quarter_label,
                'report_date': datetime.now(),
                'total_employees_in_report': len(report_context['employees']),
            }

            html_body = render_to_string('kpi/send_kpi_report_to_manager.html', email_context)

            email = EmailMessage(
                subject=subject,
                body=html_body,
                from_email=settings.DEFAULT_FROM_EMAIL,
                to=[employee.email],
            )
            email.content_subtype = "html"
            # فك التعليق لإرفاق الـ PDF عند توفير مكتبة الطباعة:
            email.attach(filename=f"KPI_Report_{quarter_month}_{year}.pdf", content=pdf_bytes, mimetype='application/pdf')

            try:
                email.send(fail_silently=False)
                sent_count += 1
            except Exception as e:
                print(f"❌ Email failed for {employee.email}: {e}")
                skipped_count += 1

        if sent_count > 0:
            messages.success(request, f"✅ KPI Report for Period Ending <strong>{quarter_label} {year}</strong> sent to {sent_count} employee(s).")
        elif skipped_count > 0:
            messages.warning(request, f"⚠️ {skipped_count} employee(s) skipped due to missing email settings.")
        return redirect('employee_kpi_list')

class EmployeeKPIDetailView(LoginRequiredMixin, AdminRequiredMixin, DetailView):
    model = CustomUser
    template_name = 'kpi/employee_kpi_detail.html'
    pk_url_kwarg = 'employee_id'

    def dispatch(self, request, *args, **kwargs):
        self.year = kwargs.get('year', date.today().year)
        self.quarter_month = kwargs.get('quarter_month', get_current_quarter_month())
        return super().dispatch(request, *args, **kwargs)

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        employee = self.object
        
        if employee.team.title == "PMO":
            templates = KPITemplate.objects.filter(Q(source="PMO"))
        elif employee.role == "leader":
            templates = KPITemplate.objects.filter(Q(source="General")|Q(source="Leader"))
        else:
            templates = KPITemplate.objects.filter(Q(source="General")|Q(source=employee.team.title))

        for template in templates:
            EmployeeKPI.objects.get_or_create(
                employee=employee,
                kpi_template=template,
                year=self.year,
                quarter_month=self.quarter_month,
                defaults={'grade': template.default_grade}
            )
        
        kpis = EmployeeKPI.objects.filter(
            employee=employee, year=self.year, quarter_month=self.quarter_month
        ).select_related('kpi_template', 'kpi_template__category')
        
        total_score = round(kpis.aggregate(Sum('score'))['score__sum'] or Decimal('0.00'), 2)
        
        EmployeeKPIFormSet = modelformset_factory(EmployeeKPI, fields=('grade', 'notes'), extra=0)
        
        if 'formset' not in context:
            context['formset'] = EmployeeKPIFormSet(queryset=kpis)
            
        context['total_score'] = total_score
        context['year'] = self.year
        context['quarter_month'] = self.quarter_month
        context['quarter_choices'] = self.get_quarter_choices()
        return context
    
    def get_quarter_choices(self):
        # بناء قائمة بالـ 4 ربع سنويات الأخيرة المتاحة للفلترة بشكل منسق مرن
        choices = []
        current_y = date.today().year
        quarters = [3, 6, 9, 12]
        
        for y in [current_y, current_y - 1]:
            for qm in sorted(quarters, reverse=True):
                label = f"Year {y} - Period Ending 31/{qm}" if qm in [3,12] else f"Year {y} - Period Ending 30/{qm}"
                choices.append((y, qm, f"{y}-{qm}", label))
        return choices[:6] # إرجاع أحدث 6 أرباع فقط
    
    def post(self, request, *args, **kwargs):
        self.object = self.get_object()
        employee = self.object
        kpis = EmployeeKPI.objects.filter(employee=employee, year=self.year, quarter_month=self.quarter_month)
        
        EmployeeKPIFormSet = modelformset_factory(EmployeeKPI, fields=('grade', 'notes'), extra=0)
        formset = EmployeeKPIFormSet(request.POST, queryset=kpis)
        
        if formset.is_valid():
            formset.save()
            messages.success(request, f"KPIs for {employee.full_name} ({self.year}-Period Ending {self.quarter_month}) updated successfully!")
            return redirect('employee_kpi_detail', employee_id=employee.id, year=self.year, quarter_month=self.quarter_month)
        else:
            messages.error(request, "There was an error updating the grades. Please check the values.")
            return self.render_to_response(self.get_context_data(formset=formset))

class MyKPIView(LoginRequiredMixin, ListView):
    template_name = 'kpi/my_kpi.html'
    
    def dispatch(self, request, *args, **kwargs):
        self.year = kwargs.get('year', date.today().year)
        self.quarter_month = kwargs.get('quarter_month', get_current_quarter_month())
        return super().dispatch(request, *args, **kwargs)
    
    def get_queryset(self):
        return EmployeeKPI.objects.filter(employee=self.request.user, year=self.year, quarter_month=self.quarter_month)
    
    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        total_score = round(self.get_queryset().aggregate(Sum('score'))['score__sum'] or Decimal('0.00'), 2)
        context['total_score'] = total_score
        context['year'] = int(self.year)
        context['quarter_month'] = int(self.quarter_month)
        
        # بناء مصفوفة الخيارات ربع السنوية يدوياً لتتوافق مع الـ Loop في الـ HTML
        # كل عنصر يحتوي على: (السنة، شهر الربع، القيمة المدمجة للـ JS، الاسم المقروء)
        context['month_choices'] = [
            (self.year, 3, f"{self.year}-3", f"Quarter 1 (Ends March)"),
            (self.year, 6, f"{self.year}-6", f"Quarter 2 (Ends June)"),
            (self.year, 9, f"{self.year}-9", f"Quarter 3 (Ends September)"),
            (self.year, 12, f"{self.year}-12", f"Quarter 4 (Ends December)"),
        ]
        return context

class KPIFeedbackCreateView(LoginRequiredMixin, AdminRequiredMixin, CreateView):
    model = KPIFeedback
    fields = ['employee', 'kpi_template', 'feedback_type', 'description', 'date', 'value']
    template_name = 'kpi/feedback_form.html'
    success_url = '/kpi/employees/'

def send_kpi_feedback(request, employee_id):
    if request.method == "POST":
        employee = get_object_or_404(CustomUser, id=employee_id) 
        year = request.POST.get('year')
        quarter_month = request.POST.get('quarter_month')
        overall_notes = request.POST.get('message')
        
        kpis = EmployeeKPI.objects.filter(employee=employee, year=year, quarter_month=quarter_month)
        total_score = sum(kpi.score for kpi in kpis) if kpis.exists() else 0
        
        if total_score >= 90: achievement_level = "Outstanding Performance"
        elif total_score >= 80: achievement_level = "Excellent Achievement"
        elif total_score >= 70: achievement_level = "Good Progress"
        else: achievement_level = "Improvement Required"

        quarter_label = get_quarter_label(int(quarter_month))
        subject = f"🚀 Performance Report: {employee.full_name} (Period Ending {quarter_label}/{year})"
        
        context = {
            'employee': employee,
            'quarter_month': quarter_month,
            'quarter_label': quarter_label,
            'year': year,
            'total_score': round(total_score, 1),
            'achievement_level': achievement_level,
            'overall_notes': overall_notes,
            'kpis': kpis,
            'logo_url': request.build_absolute_uri(settings.STATIC_URL + 'img/Smart-System-Logo.webp')
        }

        html_content = render_to_string('kpi/kpi_email_report.html', context)
        text_content = strip_tags(html_content) 

        try:
            email = EmailMultiAlternatives(subject, text_content, settings.DEFAULT_FROM_EMAIL, [employee.email])
            email.attach_alternative(html_content, "text/html")
            email.send()
            messages.success(request, f"Report sent successfully to {employee.email}")
        except Exception as e:
            messages.error(request, f"Failed to send email: {str(e)}")

    return redirect(request.META.get('HTTP_REFERER', 'employee_kpi_list'))

def accept_mission(request, pk):
    assignment = get_object_or_404(Assignement, pk=pk)
    creator = assignment.created_by
    subject = f"✅ Mission #{pk} ACCEPTED by {assignment.employee.username} - {assignment.employee.full_name}"

    message = f"""
Hello {creator.username},

Great news! 

{assignment.employee.username} has clicked "ACCEPT MISSION" and confirmed they received and understood the task.

Mission details:
• Project: {assignment.project.name if assignment.project else 'General Task'}
• Priority: {assignment.priority}
• Deadline: {assignment.deadline}

You can view the full mission here:
https://smartsystem.pythonanywhere.com/missions-list//

Best regards,
Smart Systems Command Center
"""

    send_mail(
        subject,
        message,
        settings.DEFAULT_FROM_EMAIL,
        [creator.email],
        fail_silently=False,
    )

    # Optional: nice thank-you page for the employee
    return redirect('missions_list')  # or create a simple "Mission Accepted" success page

def custom_404_view(request, exception):
    return render(request, '404.html', status=404)

from django.utils import timezone
from django.db.models import Sum
from django.utils import timezone
from django.shortcuts import get_object_or_404
from django.http import HttpResponse
from django.template.loader import render_to_string
# تأكد من استيراد الـ HTML الخاص بـ WeasyPrint أو المكتبة المستخدمة لديك
from weasyprint import HTML 

def export_kpi_pdf(request, employee_id, year, quarter_month):
    # 1. جلب الموظف بناءً على الـ ID
    employee = get_object_or_404(CustomUser, id=employee_id)
    
    # 2. تحديث الفلتر ليعتمد على quarter_month بدلاً من month
    kpis = EmployeeKPI.objects.filter(
        employee=employee, 
        year=year, 
        quarter_month=quarter_month
    ).select_related('kpi_template', 'kpi_template__category')
    
    # 3. حساب إجمالي النقاط
    total_score = kpis.aggregate(Sum('score'))['score__sum'] or 0

    # 4. تحويل رقم الربع النصي إلى صيغة مقروءة داخل الـ PDF (مثل Q1, Q2, Q3, Q4)
    quarter_mapping = {3: 'Q1', 6: 'Q2', 9: 'Q3', 12: 'Q4'}
    quarter_label = quarter_mapping.get(int(quarter_month), f"Month {quarter_month}")

    # 5. بناء محتوى الـ HTML وإرسال المتغيرات المحدثة للقالب
    html_string = render_to_string('kpi/kpi_performance_template_report.html', {
        'object': employee,
        'kpis': kpis,
        'total_score': round(total_score, 2),
        'report_date': timezone.now(), 
        'label': f"{year} - {quarter_label}",  # ستظهر بشكل منسق مثل: 2026 - Q2
    })

    # 6. توليد الـ PDF وإرجاعه كملف للتحميل
    html = HTML(string=html_string, base_url=request.build_absolute_uri())
    response = HttpResponse(content_type='application/pdf')
    response['Content-Disposition'] = f'attachment; filename="SmartSystem_Report_{employee.full_name}.pdf"'
    response.write(html.write_pdf())
    
    return response

# @login_required
# def mission_update(request, mission_id):
#     if request.method=="POST":
#         data = request.POST
#         mission = Assignement.objects.get(id=mission_id)
#         if mission.employee == request.user:
#             mission.status = data.get("status")
#             mission.save()
#             send_mail(
#                 f"Mission Status Changed for employee {mission.employee.username}",
#                 message,
#                 settings.DEFAULT_FROM_EMAIL,
#                 [creator.email],
#                 fail_silently=False,
#             )

#             messages.success(request, 'the mission Updated Successffully.')
#             return redirect('missions_list')

from .utils import get_priority_color, get_status_color

@login_required
def mission_update(request, mission_id):
    if request.method == "POST":
        mission = get_object_or_404(Assignement, id=mission_id)

        if mission.employee != request.user:
            messages.error(request, 'You are not authorized to update this mission.')
            return redirect('missions_list')

        new_status = request.POST.get("status")
        if not new_status:
            messages.error(request, 'Status is required.')
            return redirect('mission_detail', mission_id=mission_id)  # or wherever you came from

        old_status = mission.status
        mission.status = new_status
        mission.save()

        context = {
            'creator_name': mission.created_by.full_name or mission.created_by.username,
            'employee_name': mission.employee.full_name or mission.employee.username,
            'project_name': mission.project.name if mission.project else 'No Project',
            'priority': mission.priority.upper(),
            'priority_color': get_priority_color(mission.priority),
            'deadline': mission.deadline.strftime("%d %B %Y, %I:%M %p"),
            'new_status': new_status.upper(),
            'status_color': get_status_color(new_status),
            'body': mission.body,
            'updated_at': mission.updated_at.strftime("%d %B %Y at %I:%M %p"),
            'mission_detail_url': request.build_absolute_uri(
                reverse('missions_list')
            ),
        }

        html_message = render_to_string('mission_status_update.html', context)
        plain_message = strip_tags(html_message)

        subject = f"🚀 Mission Status Updated - {mission.project.name if mission.project else 'General Mission'}"

        send_mail(
            subject=subject,
            message=plain_message,
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[mission.created_by.email, 'semad@smartsystemeg.com', 'amustafa@smartsystemeg.com'],
            html_message=html_message,
            fail_silently=False,
        )

        messages.success(request, f'Mission status successfully updated to: {new_status}')
        return redirect('missions_list')

    return redirect('missions_list')

def employee_profile(request, employee_id=None):
    user = None
    if request.user.is_authenticated:
        user = request.user
    if employee_id:
        user = get_object_or_404(CustomUser, id=employee_id)
    return render(request, 'employee_profile.html', {
        "user": user

    })
from .models import Vacation  

from django.db.models import Q
from django.core.paginator import Paginator
from datetime import date

@login_required
def vacation_requests(request):
    if request.user.role in ['leader', 'delivery-manager', 'ceo'] or request.user.is_superuser or request.user.is_staff:
        base_queryset = Vacation.objects.all().order_by('-date')
    else:
        base_queryset = Vacation.objects.filter(user=request.user).order_by('-date')

    search_query = request.GET.get('search', '')
    status_filter = request.GET.get('status', '')
    date_filter = request.GET.get('date', '')

    filtered_queryset = base_queryset
    
    if search_query:
        filtered_queryset = filtered_queryset.filter(
            Q(user__username__icontains=search_query) | 
            Q(user__full_name__icontains=search_query) |
            Q(reason__icontains=search_query)
        )
    
    if status_filter:
        filtered_queryset = filtered_queryset.filter(status=status_filter)
        
    if date_filter:
        filtered_queryset = filtered_queryset.filter(date=date_filter)

    paginator = Paginator(filtered_queryset, 3) 
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    today = date.today()
    vacations_this_month = base_queryset.filter(
        date__year=today.year,
        date__month=today.month
    ).count()

    context = {
        'vacations': page_obj,          
        'page_obj': page_obj,           
        'vacations_this_month': vacations_this_month,
        'current_month': today.replace(day=1),
        'search_query': search_query,
        'status_filter': status_filter,
        'date_filter': date_filter,
    }
    
    return render(request, 'vacation_requests.html', context)

@login_required
def add_vacations(request):
    if request.method == "POST":
        data = request.POST
        obj = Vacation.objects.create(
            user = request.user,
            date = data.get("date"),
            reason = data.get("reason"),
            duration = data.get("duration"),
            status = "pending",

                )
        subject = f"🚀 New Vacation Request: {obj.user.username}"

        vacation_url = request.build_absolute_uri(reverse("vacation_requests"))
        html_message = render_to_string('vacation_request_email.html', {
                'vacation': obj,
                'vacation_url': vacation_url              
            })
        if obj.user.role in ['delivery-manager', 'top-manager']:
            sent_to = "afarouk@smartsystemeg.com"
        else:
            sent_to = "semad@smartsystemeg.com" 
        send_mail(
            subject,
            "", 
            settings.DEFAULT_FROM_EMAIL,
            [sent_to],
            html_message=html_message,
            fail_silently=False,
        )
        
        messages.success(request, 'Vacation Request Sent success')
        return redirect('vacation_requests')

from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string

@login_required
def process_vacation(request):
    if request.method == "POST" and (request.user.is_staff or request.user.role in ['leader', 'ceo']):
        v_id = request.POST.get('vacation_id')
        action = request.POST.get('status_action')
        reject_reason = request.POST.get('reject_reason', '')

        vacation = Vacation.objects.get(id=v_id)
        vacation.status = action
        vacation.save()

        # --- Email Logic ---
        subject = f"Vacation Request Update: {action.capitalize()}"
        template = 'vacation_status_email.html'
        
        context = {
            'employee_name': vacation.user.full_name,
            'status': action,
            'date': vacation.date,
            'duration': vacation.duration,
            'reject_reason': reject_reason if action == 'rejected' else None,
            'site_url': request.build_absolute_uri(reverse("vacation_requests"))
        }

        html_content = render_to_string(template, context)
        msg = EmailMultiAlternatives(subject, strip_tags(html_content), settings.DEFAULT_FROM_EMAIL, [vacation.user.email])
        msg.attach_alternative(html_content, "text/html")
        msg.send()

        messages.success(request, f"Vacation request for {vacation.user.username} has been {action}.")
        return redirect('vacation_requests')

from .models import employeeProfile
@login_required
def employee_settings(request):
    try:
        user = request.user
        profile, created = employeeProfile.objects.get_or_create(user=user)
        if request.method=="POST":
            
            data = request.POST
            profile.job_title = data.get("job_title")
            if request.FILES.get("image"):
                profile.image = request.FILES.get("image")
            if request.FILES.get("cv"):
                profile.cv = request.FILES.get("cv")
            profile.phone = data.get("phone")
            profile.bio = data.get("bio")
            profile.linkedin = data.get("linkedin")
            profile.save()
            messages.success(request, "Profile Updated Successfully.")
            return redirect('settings')
        return render(request, 'settings.html', {
            "profile": profile
        })
    except Exception as e:
        messages.warning(request, f"Error Happen {e}")
        return redirect("settings")
from django.contrib.auth.decorators import login_required
from django.shortcuts import render
from django.http import JsonResponse
from django.utils import timezone
from .utils import extract_skills_from_pdf
from .models import employeeProfile   # ← your real model


@login_required
def skills_dashboard(request):
    context = {
        'is_admin': request.user.is_staff,
    }

    if request.user.is_staff:
        # ==================== ADMIN VIEW ====================
        profiles = employeeProfile.objects.select_related('user').exclude(user__is_superuser=True)

        users_data = []
        for profile in profiles:
            users_data.append({
                'user': profile.user,
                'skills': profile.skills or [],      # ← now it's always a list
                'has_cv': bool(profile.cv),
            })

        context['users_data'] = users_data

    else:
        # ==================== EMPLOYEE VIEW ====================
        try:
            profile = request.user.profile          # this works because of related_name='profile'
            context['my_skills'] = profile.skills or []
        except employeeProfile.DoesNotExist:
            context['my_skills'] = []

    return render(request, 'skills.html', context)
from django.contrib import messages
from django.shortcuts import redirect
from django.contrib.auth.decorators import login_required
from django.utils import timezone
from .utils import extract_skills_from_pdf
from .models import employeeProfile   # Make sure to import your model


@login_required
def upload_cv(request):
    if request.method == 'POST' and request.FILES.get('resume'):
        resume_file = request.FILES['resume']

        # Security: Only allow PDF files
        if not resume_file.name.lower().endswith('.pdf'):
            messages.error(request, 'Only PDF files are allowed!')
            return redirect('skills')

        try:
            # Get the user's profile
            profile, created = employeeProfile.objects.get_or_create(user=request.user)

            # 1. Extract skills using your AI utility
            skills = extract_skills_from_pdf(resume_file)

            # 2. Save the CV file properly
            profile.cv = resume_file          # ← Direct assignment (this is correct)

            # 3. Save extracted skills and timestamp
            profile.skills = skills
            profile.cv_uploaded_at = timezone.now()
            profile.save()

            messages.success(request, f'CV uploaded successfully! {len(skills)} skills extracted.')
            return redirect('skills')

        except Exception as e:
            messages.error(request, f'Error processing CV: {str(e)}')
            return redirect('skills')

    # If GET request (direct access)
    messages.warning(request, 'Please upload a CV using the form.')
    return redirect('skills')

@login_required
def re_extract_skills(request, user_id):
   
    try:
        profile = employeeProfile.objects.select_related('user').get(user_id=user_id)

        if not profile.cv:
            return JsonResponse({
                'status': 'error',
                'message': 'This user has not uploaded a CV yet.'
            })

        # Re-extract skills from the saved CV
        with profile.cv.open('rb') as file_obj:
            new_skills = extract_skills_from_pdf(file_obj)

        profile.skills = new_skills
        profile.save()

        return JsonResponse({
            'status': 'success',
            'skills': new_skills,
            'message': f'Successfully re-extracted {len(new_skills)} skills.'
        })

    except employeeProfile.DoesNotExist:
        return JsonResponse({'status': 'error', 'message': 'Profile not found.'})
    except Exception as e:
        return JsonResponse({'status': 'error', 'message': str(e)})


from django.shortcuts import render
from django.http import StreamingHttpResponse
from django.views.decorators.csrf import csrf_exempt
import json
from groq import Groq
import os

# Initialize Groq client
client = Groq(api_key="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")


@csrf_exempt
def ask_groq(request):
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            user_message = data.get('message', '').strip()

            if not user_message:
                return StreamingHttpResponse(
                    "data: " + json.dumps({"content": "Please type a message."}) + "\n\n",
                    content_type='text/event-stream'
                )

            def stream_response():
                try:
                    completion = client.chat.completions.create(
                        model="llama-3.3-70b-versatile",
                        messages=[
                            {"role": "system", "content": "You are a helpful, friendly, and concise assistant."},
                            {"role": "user", "content": user_message}
                        ],
                        temperature=0.7,
                        max_tokens=1500,
                        stream=True,                    # ← This enables real-time streaming
                    )

                    for chunk in completion:
                        if chunk.choices[0].delta.content:
                            content = chunk.choices[0].delta.content
                            yield f"data: {json.dumps({'content': content})}\n\n"

                    # Send done signal
                    yield "data: [DONE]\n\n"

                except Exception as e:
                    yield f"data: {json.dumps({'content': 'Sorry, an error occurred while processing your request.'})}\n\n"
                    yield "data: [DONE]\n\n"

            return StreamingHttpResponse(
                stream_response(),
                content_type='text/event-stream',
                headers={
                    'Cache-Control': 'no-cache',
                    'X-Accel-Buffering': 'no'   # Important for streaming on some servers
                }
            )

        except json.JSONDecodeError:
            return StreamingHttpResponse(
                "data: " + json.dumps({"content": "Invalid request format."}) + "\n\n",
                content_type='text/event-stream'
            )
        except Exception as e:
            return StreamingHttpResponse(
                "data: " + json.dumps({"content": f"Server error: {str(e)}"}) + "\n\n",
                content_type='text/event-stream'
            )

    return StreamingHttpResponse(
        "data: " + json.dumps({"content": "Method not allowed."}) + "\n\n",
        content_type='text/event-stream'
    )

def chatbot(request):
    return render(request, 'askAI.html', {})


from django.shortcuts import render
from django.http import JsonResponse
from django.db.models import Sum, Min
from datetime import datetime, timedelta
from decimal import Decimal
from collections import defaultdict

from .models import CustomUser, TimesheetEntry, Vacation


def get_workdays(start_date, end_date, user=None):
    """Egypt work schedule: Sunday → Thursday are workdays (Fri + Sat = weekend)"""
    if start_date > end_date:
        return 0
    
    workdays = 0
    current = start_date
    while current <= end_date:
        # Sunday(6), Monday(0), Tuesday(1), Wednesday(2), Thursday(3) = workdays
        if current.weekday() in [6, 0, 1, 2, 3]:
            workdays += 1
        current += timedelta(days=1)

    # Subtract approved vacations
    if user:
        vacations = Vacation.objects.filter(
            user=user,
            date__range=[start_date, end_date],
            status='approved'
        )
        vacation_days = sum(v.duration for v in vacations)
        workdays = max(0, workdays - vacation_days)

    return workdays


def utilization_report(request):
    """CEO Utilization Report - Shows ALL data by default"""
    end_date = datetime.now().date()

    # ==================== DEFAULT = ALL DATA (first load) ====================
    start_date_str = request.GET.get('start_date')
    end_date_str = request.GET.get('end_date')

    if start_date_str and end_date_str:
        start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
    else:
        # FIRST LOAD → show ALL historical data automatically
        min_date = TimesheetEntry.objects.aggregate(min_date=Min('work_date'))['min_date']
        start_date = min_date if min_date else (end_date - timedelta(days=365))  # fallback 1 year

    # Get all active employees
    employees = CustomUser.objects.filter(is_active=True).exclude(Q(role__in=["top-manager","project-manager", "admin","ceo", "delivery-manager"]) | Q(team__title__in=["PMO"])).select_related('team').order_by('username')

    employee_data = []
    for emp in employees:
        # Filter entries (exclude drafts)
        entries_qs = TimesheetEntry.objects.filter(
            user=emp,
            work_date__range=[start_date, end_date]
        ).exclude(status='DRAFT')

        total_hours = entries_qs.aggregate(total=Sum('hours'))['total'] or Decimal('0.00')
        workdays = get_workdays(start_date, end_date, emp)
        expected_hours = workdays * 8
        utilization = (float(total_hours) / expected_hours * 100) if expected_hours > 0 else 0

        employee_data.append({
            'id': emp.id,
            'username': emp.username,
            'full_name': emp.full_name or emp.username,
            'team': emp.team.title if emp.team else 'No Team',
            'total_hours': round(float(total_hours), 2),
            'expected_hours': expected_hours,
            'utilization': round(utilization, 2),
            'entries_count': entries_qs.count(),
        })

    context = {
        'start_date': start_date.strftime('%Y-%m-%d'),
        'end_date': end_date.strftime('%Y-%m-%d'),
        'employee_json': json.dumps(employee_data),   # ← important for JS
        'total_employees': len(employee_data),
        'avg_utilization': round(sum(e['utilization'] for e in employee_data) / len(employee_data), 1) if employee_data else 0,
    }
    
    return render(request, 'utilization.html', context)


def employee_utilization_detail(request, employee_id):
    """Ajax detail for modal (same Egypt logic)"""
    start_str = request.GET.get('start_date')
    end_str = request.GET.get('end_date')

    start_date = datetime.strptime(start_str, '%Y-%m-%d').date()
    end_date = datetime.strptime(end_str, '%Y-%m-%d').date()

    emp = CustomUser.objects.get(id=employee_id)

    entries = TimesheetEntry.objects.filter(
        user=emp,
        work_date__range=[start_date, end_date]
    ).exclude(status='DRAFT').select_related('project').order_by('-work_date')

    total_hours = entries.aggregate(total=Sum('hours'))['total'] or Decimal('0')
    workdays = get_workdays(start_date, end_date, emp)
    expected_hours = workdays * 8
    utilization = (float(total_hours) / expected_hours * 100) if expected_hours > 0 else 0

    # Project breakdown for pie
    project_hours = defaultdict(float)
    for entry in entries:
        project_hours[entry.project.name] += float(entry.hours)

    # Task type breakdown
    task_hours = defaultdict(float)
    for entry in entries:
        task_hours[entry.task_type] += float(entry.hours)

    entries_list = [{
        'work_date': e.work_date.strftime('%Y-%m-%d'),
        'project': e.project.name,
        'task_description': e.task_description[:120] + '...' if len(e.task_description) > 120 else e.task_description,
        'hours': float(e.hours),
        'status': e.status,
        'task_type': e.task_type,
    } for e in entries]

    return JsonResponse({
        'employee_name': emp.full_name or emp.username,
        'utilization': round(utilization, 2),
        'total_hours': round(float(total_hours), 2),
        'expected_hours': expected_hours,
        'project_data': [{'project': p, 'hours': round(h, 2)} for p, h in project_hours.items()],
        'task_data': [{'type': t, 'hours': round(h, 2)} for t, h in task_hours.items()],
        'entries': entries_list,
    })