from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import CustomUser, TimesheetEntry, Project, Timesheet, ProjectCost
admin.site.register([ TimesheetEntry, Project, Timesheet, ProjectCost])
class CustomUserAdmin(UserAdmin):
    # Fields shown in list view
    list_display = ('username', 'full_name', 'role', 'is_active', 'is_staff')
    list_filter = ('role', 'is_active', 'is_staff')
    search_fields = ('username', 'full_name')

    # Fieldsets for editing users
    fieldsets = (
        (None, {'fields': ('username', 'password')}),
        ('Personal Info', {'fields': ('full_name', 'role')}),
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
