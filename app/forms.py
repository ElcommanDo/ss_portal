# In forms.py
from django import forms
from django.forms import modelformset_factory
from .models import KPITemplate, EmployeeKPI

class KPITemplateForm(forms.ModelForm):
    class Meta:
        model = KPITemplate
        fields = '__all__'

# For editing employee KPIs: Use formset in views
EmployeeKPIFormSet = modelformset_factory(EmployeeKPI, fields=('grade', 'notes'), extra=0)