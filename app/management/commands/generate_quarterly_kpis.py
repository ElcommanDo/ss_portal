import datetime
from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from app.models import KPITemplate, EmployeeKPI

User = get_user_model()

class Command(BaseCommand):
    help = 'Automatically opens KPI sheets at the BEGINNING of each quarter so managers can edit them throughout the period.'

    def handle(self, *args, **options):
        today = datetime.date.today()
        year = today.year
        
        # Determine the quarter month target
        if today.month in [1, 2, 3]: 
            quarter_month = 3
        elif today.month in [4, 5, 6]: 
            quarter_month = 6
        elif today.month in [7, 8, 9]: 
            quarter_month = 9
        else: 
            quarter_month = 12

        self.stdout.write(f"Opening KPI sheets for the new active period ending: {quarter_month}/{year}...")

        # select_related('team') reduces database hits inside the loop
        employees = User.objects.filter(is_active=True).select_related('team')
        templates = KPITemplate.objects.all()
        
        created_count = 0
        skipped_count = 0

        for employee in employees:
            # Fallback if employee.team is null/None
            team_title = employee.team.title if employee.team else None

            if team_title == "PMO":
                emp_templates = templates.filter(source="PMO")
            elif employee.role == "leader":
                emp_templates = templates.filter(source__in=["General", "Leader"])
            else:
                # If no team, only assign "General" templates to prevent errors
                filter_teams = ["General"]
                if team_title:
                    filter_teams.append(team_title)
                emp_templates = templates.filter(source__in=filter_teams)

            for template in emp_templates:
                # This ensures sheets are ONLY created if they are missing
                kpi, created = EmployeeKPI.objects.get_or_create(
                    employee=employee,
                    kpi_template=template,
                    year=year,
                    quarter_month=quarter_month,
                    defaults={
                        'grade': template.default_grade,
                        'notes': ""
                    }
                )
                if created:
                    created_count += 1
                else:
                    skipped_count += 1

        self.stdout.write(self.style.SUCCESS(
            f"Successfully opened {created_count} KPI sheets. {skipped_count} sheets already existed."
        ))