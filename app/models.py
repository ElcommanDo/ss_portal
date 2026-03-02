from django.db import models
from django.contrib.auth.models import BaseUserManager
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin
from django.db import models
from django.core.exceptions import ValidationError
from django.core.validators import MinValueValidator


class CustomUserManager(BaseUserManager):
    def create_user(self, username, password=None, **extra_fields):
        if not username:
            raise ValueError("Users must have a username")
        user = self.model(username=username, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, username, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        return self.create_user(username, password, **extra_fields)



class Team(models.Model):
    title = models.CharField(max_length=100)
    team_lead = models.CharField(max_length=220, null=True)

    

class CustomUser(AbstractBaseUser, PermissionsMixin):
    ROLE_CHOICES = [
        ('admin', 'Administrator'),
        ('developer', 'Developer'),
        ('sales', 'Sales'),
        ('ceo', 'CEO '),
        ('project-manager', 'Project Manager'),        
        ('leader', 'Leader'),
        ('top-manager', 'Top Manager'),        
        ('delivery-manager', 'Delivery Manager'),        
        ('engineer', 'Engineer'),
        

    ]

    username = models.CharField(max_length=150, unique=True)
    role = models.CharField(max_length=20, choices=ROLE_CHOICES)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    full_name = models.CharField( max_length=220, default='User')
    team = models.ForeignKey(Team, on_delete=models.SET_NULL,
                              null=True, blank=True, related_name="employees")
    objects = CustomUserManager()
    date_joined = models.DateTimeField(auto_now_add=True)
    email = models.EmailField(null=True, blank=True)
    USERNAME_FIELD = 'username'
    REQUIRED_FIELDS = ['role']

    def __str__(self):
        return self.username

    def save(self, *args, **kwargs):
        if self.role in ['admin', 'project-manager', 'ceo', 'top-manager', 'delivery-manager', 'leader']:
            self.is_staff = True
        return super().save(*args, **kwargs)
    
    class Meta:
        ordering = ('-date_joined',)
    
    

class Project(models.Model):
    name = models.CharField(max_length=150, unique=True)
    description = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    is_public = models.BooleanField(default=False)
    created_by = models.ForeignKey(CustomUser, on_delete=models.PROTECT, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name
    
    class Meta:
        ordering = ['name']
        verbose_name_plural = "Projects"


class Timesheet(models.Model):
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    date = models.DateField() 
    
    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'date'], 
                name='unique_user_date_timesheet'
            )
        ]
        ordering = ['date'] 

    def __str__(self):
        return f"{self.user.username} - {self.date}"


class TimesheetEntry(models.Model):
    STATUS_CHOICES = [
        ('Inprogress', 'In Progress'),
        ('APPROVED', 'Approved'),
        ('REJECTED', 'Rejected'),
        ('COMPLETED', 'Completed'),
        
        ('DRAFT', 'Draft'),
    ]

    task_type = models.CharField(max_length=20,
        choices=(("Delivery","Delivery"), ("Pre-Sale", "Pre-Sale"), ("study", "Study / Training")), default="Delivery")

    user = models.ForeignKey(
        CustomUser, 
        on_delete=models.CASCADE, 
        related_name='timesheets',
        verbose_name="Assigned By/User"
    )
    
    project = models.ForeignKey(
        Project, 
        on_delete=models.PROTECT,
        related_name='entries'
    )
    
    task_description = models.TextField()
    
    hours = models.DecimalField(
        max_digits=5, 
        decimal_places=2,
        validators=[MinValueValidator(0.01)],
        help_text="Hours must be greater than zero."
    )
    
    work_date = models.DateField() 
    status = models.CharField(
        max_length=10, 
        choices=STATUS_CHOICES, 
        default='Inprogress'
    )
    time_sheet = models.ForeignKey(Timesheet, on_delete=models.CASCADE,
                                    null=True, related_name='tasks') 
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_scheduled = models.BooleanField(default=False)
    time_start = models.TimeField(null=True, blank=True)
    time_end = models.TimeField(null=True, blank=True)
    onsite_abroad = models.BooleanField(default=False)
    onsite_Egypt = models.BooleanField(default=False)
    
    def __str__(self):
        return f"{self.user.username} - {self.project.name} on {self.work_date}"
        
    class Meta:
        ordering = ['-work_date', '-created_at']
        verbose_name = "Timesheet Entry"
        verbose_name_plural = "Timesheet Entries"
   

class ProjectCost(models.Model):
    amount = models.DecimalField(decimal_places=2, max_digits=11)
    cost_type = models.CharField(max_length=60)
    user = models.ForeignKey(CustomUser, on_delete=models.PROTECT)
    project = models.ForeignKey(Project, on_delete=models.PROTECT)
    notes = models.TextField(default='')
    currency = models.CharField(max_length=5)

    

class Assignement(models.Model):
    employee = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name="my_assignements")
    body = models.TextField()
    priority = models.CharField(max_length=8)
    project = models.ForeignKey(Project, null=True, blank=True, on_delete=models.PROTECT)
    status = models.CharField(max_length=30)
    is_task = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    created_by = models.ForeignKey(CustomUser, on_delete=models.CASCADE,
                                   related_name="created_assignements")
    deadline = models.DateTimeField()



from django.db import models
from django.conf import settings

# 1. KPI Definition (The Master Record)
class KPI(models.Model):
    title = models.CharField(max_length=100)
    description = models.TextField(blank=True, null=True)
    # This acts as the starting point for everyone (e.g., 100%)
    base_score = models.IntegerField(default=100)
    icon_class = models.CharField(max_length=50, default="fas fa-chart-line") 
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.title

# 2. Employee KPI Score (The Live State)
class EmployeeKPIScore(models.Model):
    employee = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="kpi_scores")
    kpi = models.ForeignKey(KPI, on_delete=models.CASCADE)
    # The actual current points the employee has
    current_score = models.IntegerField(default=100)
    last_updated = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('employee', 'kpi')

    def __str__(self):
        return f"{self.employee.username} - {self.kpi.title}: {self.current_score}"

# 3. Deduction/Log (The History & Audit Trail)
class KPILog(models.Model):
    employee = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    kpi = models.ForeignKey(KPI, on_delete=models.CASCADE)
    points_changed = models.IntegerField() # e.g., -10
    reason = models.TextField()
    admin_actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="kpi_actions")
    timestamp = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.employee.username} | {self.points_changed} pts | {self.kpi.title}"