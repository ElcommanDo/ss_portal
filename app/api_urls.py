"""URLs for the mobile app JSON API — mounted at /api/v1/ in config/urls.py."""
from django.urls import path

from . import api_views as api

urlpatterns = [
    # auth
    path("auth/login/", api.login, name="api_login"),
    path("auth/me/", api.me, name="api_me"),
    path("auth/change-password/", api.change_password, name="api_change_password"),

    # common
    path("meta/", api.meta, name="api_meta"),
    path("dashboard/", api.dashboard, name="api_dashboard"),

    # my timesheets
    path("my/timesheets/", api.my_timesheets, name="api_my_timesheets"),
    path("timesheets/<int:pk>/entries/", api.timesheet_entries, name="api_timesheet_entries"),
    path("entries/", api.entries, name="api_entries"),
    path("entries/<int:pk>/", api.entry_detail, name="api_entry_detail"),

    # KPI
    path("kpi/my/", api.my_kpi, name="api_my_kpi"),

    # missions
    path("missions/", api.missions, name="api_missions"),
    path("missions/<int:pk>/", api.mission_detail, name="api_mission_detail"),
    path("missions/<int:pk>/status/", api.mission_status, name="api_mission_status"),
    path("missions/<int:pk>/accept/", api.mission_accept, name="api_mission_accept"),
    path("missions/<int:pk>/remind/", api.mission_remind, name="api_mission_remind"),

    # vacations
    path("vacations/", api.vacations, name="api_vacations"),
    path("vacations/<int:pk>/process/", api.vacation_process, name="api_vacation_process"),
    path("vacations/<int:pk>/cancel/", api.vacation_cancel, name="api_vacation_cancel"),

    # management
    path("review/timesheets/", api.review_timesheets, name="api_review_timesheets"),
    path("users/", api.users_list, name="api_users"),
    path("users/<int:pk>/toggle-active/", api.user_toggle_active, name="api_user_toggle_active"),
    path("teams/", api.teams_list, name="api_teams"),
    path("teams/<int:pk>/members/", api.team_members, name="api_team_members"),
    path("projects/", api.projects, name="api_projects"),
    path("projects/<int:pk>/costs/", api.project_add_cost, name="api_project_add_cost"),

    # reports
    path("reports/man-days/", api.report_man_days, name="api_report_man_days"),
    path("reports/man-days/pdf/", api.pdf_man_days, name="api_report_man_days_pdf"),
    path("reports/last-timesheet/", api.report_last_timesheet, name="api_report_last_timesheet"),
    path("reports/last-timesheet/pdf/", api.pdf_last_timesheet, name="api_report_last_timesheet_pdf"),
    path("reports/monthly-man-days/", api.report_monthly_man_days, name="api_report_monthly"),
    path("reports/monthly-man-days/pdf/", api.pdf_monthly_man_days, name="api_report_monthly_pdf"),
    path("reports/project-costs/", api.report_project_costs, name="api_report_project_costs"),
    path("reports/utilization/", api.report_utilization, name="api_report_utilization"),
    path("reports/utilization/<int:employee_id>/", api.report_utilization_detail, name="api_report_utilization_detail"),
    path("reports/employee-activity/", api.report_employee_activity, name="api_report_employee_activity"),
]
