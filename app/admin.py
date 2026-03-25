from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from . import models
from .models import CustomUser, TimesheetEntry, Project, Assignement, Timesheet, ProjectCost, Team

admin.site.register([ProjectCost, Assignement, models.KPITemplate, models.KPICategory, models.EmployeeKPI, models.KPIFeedback])
from import_export.admin import ImportExportModelAdmin
from .resources import (
    TeamResource,
    CustomUserResource,
    ProjectResource
)
class CustomUserAdmin(UserAdmin, ImportExportModelAdmin):
    # Fields shown in list view
    list_display = ('username', 'full_name', 'role', 'is_active', 'is_staff')
    list_filter = ('role', 'is_active', 'is_staff')
    search_fields = ('username', 'full_name')
    resource_class = CustomUserResource

    # Fieldsets for editing users
    fieldsets = (
        (None, {'fields': ('username', 'password')}),
        ('Personal Info', {'fields': ('full_name', 'role', 'email')}),
        ('Permissions', {'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')}),
    )

    # Fieldsets for creating users
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('username', 'full_name', 'role', 'password1', 'password2', 'is_staff', 'is_active')}
        ),
    )

    ordering = ('username',)

admin.site.register(CustomUser, CustomUserAdmin)

@admin.register(Team)
class TeamAdmin(ImportExportModelAdmin):
    resource_class = TeamResource




@admin.register(Timesheet)
class TimeSheetAdmin(admin.ModelAdmin):
    list_filter = ['date']



@admin.register(TimesheetEntry)
class TimeSheetEntryAdmin(admin.ModelAdmin):
    list_filter = ['work_date']

    

@admin.register(Project)
class ProjectAdmin(ImportExportModelAdmin):
    resource_class = ProjectResource