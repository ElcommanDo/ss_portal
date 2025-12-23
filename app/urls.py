
from django.urls import path
from . import views
urlpatterns = [
    path('', views.login_request, name='login'),
    path('logout/', views.logout_request, name='logout'),
    
    path('home/', views.timesheet_dashboard, name='home'),
    path('add-timesheet/', views.timesheet_create, name='add_timesheet'),
    path('projects/', views.projects, name='projects'),
    path('users/', views.users, name='users'),
    path('user-create/', views.user_create, name='user_create'),
    path('team-create/', views.team_create, name='team_create'),
    
    path('teams/', views.teams, name='teams'),
    path('team-create/', views.team_create, name='team_create'),
   
    path('project-create/', views.project_create, name='project_create'),
    path('users/edit/<int:pk>/', views.user_edit, name='user_edit'), 
    path('team/edit/<int:pk>/', views.team_edit, name='team_edit'), 
    path('team/delete/<int:pk>/', views.team_delete, name='team_delete'), 
    
    path('users/status/<int:pk>/', views.toggle_user_status, name='user_toggle_status'),
    path('export_csv/', views.export_csv, name="export_csv"),
    path('Change-password/', views.change_password, name='change_password'),
    path('team-members/<int:pk>/', views.team_members, name='team_members'),
    path('timesheets/', views.timesheet, name='timesheet'),
    path('scheduled-timesheets/<str:scheduled>/', views.timesheet, name='scheduled_timesheet'),
    path('timesheet-update/<int:pk>/', views.timesheet_update, name='timesheet_update'),
    path('timesheet-delete/<int:pk>/', views.time_sheet_delete, name='timesheet_delete'),
    
    path('project-timesheets/<int:pk>/', views.project_timesheets, name='project_timesheets'),
    path('timesheets/entry-detail/<int:pk>/', views.timesheet_detail_entries, name='timesheet_detail_entries'),
    path('my-timesheets/', views.user_timesheets, name='user_timesheets'),
    path('my-schduled-timesheets/<str:scheduled>/', views.user_timesheets, name='scheduled_user_timesheets'), 
    path('my_timesheet_entries/<int:pk>/', views.my_timesheet_entries, name='my_timesheet_entries'), 
    path('timesheet_entries/<int:pk>/', views.timesheet_entries, name='timesheet_entries'), 
    path('add-project-cost/', views.add_project_cost, name='add_project_cost'),
    path('reports/', views.reports, name='reports_dashboard'),
    path('reports/man-days/', views.reports_daily_man_days, name='reports_man_days'),
    path('reports/project-cost-summary/', views.reports_project_cost, name='reports_project_cost_summary'),
    path('reports/status-compliance/', views.reports_status_compliance, name='reports_status_compliance'),
    path('reports/employee-activity/', views.reports_employee_activity, name='reports_employee_activity'),
    path('reports/public-health/', views.reports_public_project_health, name='reports_public_project_health'),
    path('download_sqlite/', views.download_sqlite, name='download_sqlite'),
    path('bulk-uplaod-tiemsheets/', views.timesheet_bulk_upload, name="timesheet_bulk_upload"),
    path('export_man_days_pdf', views.export_man_days_pdf, name='export_man_days_pdf')
]
