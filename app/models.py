from django.db import models
from django.contrib.auth.models import BaseUserManager,PermissionsMixin, AbstractBaseUser, PermissionsMixin
from django.conf import settings
from django.core.validators import MinValueValidator, MaxValueValidator
from decimal import Decimal

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
    TITLES = [
        ('Infra_Team', 'Infra_Team'),
        ('Maximo_Functional', 'Maximo_Functional'),
        ('Maximo_Technical', 'Maximo_Technical'),
        ('PMO', 'PMO'),
        ('SDM', 'SDM'),
        ('Top_mgmt', 'Top_mgmt'),
        
        
    ]
    title = models.CharField(max_length=100, choices=TITLES)
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

class employeeProfile(models.Model):
    user = models.OneToOneField(CustomUser, related_name='profile', on_delete=models.CASCADE)
    job_title = models.CharField(max_length=220, default='Smart System Engineer')
    image = models.ImageField(upload_to='emp_images', null=True, blank=True)
    phone = models.CharField(max_length=18, default='01xxxxxxxxxx')
    bio = models.TextField(default=' ')
    linkedin = models.URLField(default='https://Example.linkedin.com/profile')
    cv = models.FileField(upload_to="CVs", null=True, blank=True)

class Skill(models.Model):
    profile = models.ForeignKey(employeeProfile, on_delete=models.CASCADE, related_name='skills')
    title = models.CharField(max_length=220)
    level = models.IntegerField(validators=[MinValueValidator(0), MaxValueValidator(100)])

class Certificate(models.Model):
    profile = models.ForeignKey(employeeProfile, on_delete=models.CASCADE, related_name='certificates')
    certificate_title = models.CharField(max_length=220)
    obtain_date = models.DateField()
    description = models.TextField(default=' ')


class Experience(models.Model):
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    still_in_work = models.BooleanField(default=False)
    title = models.CharField(max_length=220)
    description = models.TextField(default=' ')

    
class Vacation(models.Model):
    user = models.ForeignKey(CustomUser, on_delete=models.CASCADE)
    date = models.DateField()
    reason = models.TextField(default=' ')
    duration = models.IntegerField()
    status = models.CharField( max_length=13, choices=(
        ('pending', 'Pending'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
        ('cancelled', 'Cancelled'),
        
          
    ))



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


class KPICategory(models.Model):
    name = models.CharField(max_length=100, unique=True)  # e.g., 'Project/Services Based KPIs', 'Personal KPIs', 'Business Contribution KPIs'
    
    def __str__(self):
        return self.name

    class Meta:
        verbose_name_plural = "KPI Categories"
        ordering = ['name']


class KPITemplate(models.Model):
    SOURCE = [
       ('Infra_Team', 'Infra_Team'),
        ('Maximo_Functional', 'Maximo_Functional'),
        ('Maximo_Technical', 'Maximo_Technical'),
        ('PMO', 'PMO'),
        ('SDM', 'SDM'),
        ('Top_mgmt', 'Top_mgmt'),
        ('General', 'General'),
        ('Leader', 'Leader')
              ]
    source = models.CharField(max_length=50, choices=SOURCE, default='General')
    category = models.ForeignKey(KPICategory, on_delete=models.PROTECT, related_name='kpis')
    description = models.TextField()
    way_of_measure = models.TextField(help_text="Describe how the grade is measured, e.g., '(Fulfilled=10, Conflict in one=6, two=0)'")
    default_grade = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal('10.00'), validators=[MinValueValidator(0)])
    max_grade = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal('10.00'), help_text="Maximum possible grade (can be >10 for overachievement)")
    weight = models.DecimalField(max_digits=5, decimal_places=2, validators=[MinValueValidator(0)], help_text="Weight in percentage, e.g., 12.00 for 12%")
    notes = models.TextField(blank=True)
    
    def __str__(self):
        return f"{self.description[:50]}... ({self.weight}%)"

    class Meta:
        ordering = ['category', 'description']
        verbose_name_plural = "KPI Templates"


class EmployeeKPI(models.Model):
    employee = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name='kpis')
    kpi_template = models.ForeignKey(KPITemplate, on_delete=models.PROTECT)
    grade = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal('10.00'), validators=[MinValueValidator(0)])
    score = models.DecimalField(max_digits=5, decimal_places=2, blank=True, help_text="Automatically calculated as (grade / 10) * weight")
    notes = models.TextField(blank=True)
    updated_at = models.DateTimeField(auto_now=True)
    year = models.PositiveIntegerField()  # e.g., 2026
    month = models.PositiveIntegerField(validators=[MinValueValidator(1), MaxValueValidator(12)])  # 1-12
    def save(self, *args, **kwargs):
        # Automatic calculation: score = (grade / 10) * weight
        # This allows overachievement if grade > 10 (e.g., 15 / 10 * weight = 1.5 * weight)
        self.score = (self.grade / Decimal('10')) * self.kpi_template.weight
        super().save(*args, **kwargs)
    
    def __str__(self):
        return f"{self.employee.username} - {self.kpi_template.description[:20]}... ({self.year}-{self.month:02d})"
    class Meta:
        unique_together = ['employee', 'kpi_template', 'year', 'month']
        ordering = ['-year', '-month', 'kpi_template__category', 'kpi_template']
        verbose_name_plural = "Employee KPIs"


# Optional: For semi-automation, add a Complaint/Feedback model to track issues
# This can be used to auto-deduct grades for certain KPIs (e.g., complaint-based)
class KPIFeedback(models.Model):
    FEEDBACK_TYPE_CHOICES = [
        ('complaint', 'Complaint'),
        ('issue', 'Issue'),
        ('conflict', 'Conflict'),
        ('breach', 'Breach'),
        ('lead', 'Lead Generated'),  # For business KPIs
        ('idea', 'Idea Submitted'),
    ]
    
    employee = models.ForeignKey(CustomUser, on_delete=models.CASCADE, related_name='kpi_feedback')
    kpi_template = models.ForeignKey(KPITemplate, on_delete=models.PROTECT, null=True, blank=True, help_text="Link to specific KPI if applicable")
    feedback_type = models.CharField(max_length=20, choices=FEEDBACK_TYPE_CHOICES)
    description = models.TextField()
    date = models.DateField()
    value = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal('0.00'), help_text="Numeric value, e.g., 1 for one complaint, or 15 for qualified lead")
    created_by = models.ForeignKey(CustomUser, on_delete=models.PROTECT, related_name='created_feedback')
    
    def __str__(self):
        return f"{self.employee.username} - {self.feedback_type} on {self.date}"

    class Meta:
        ordering = ['-date']

