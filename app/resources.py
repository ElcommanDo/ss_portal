from import_export import resources, fields
from import_export.widgets import ForeignKeyWidget
from .models import Team, CustomUser, Project

class TeamResource(resources.ModelResource):
    class Meta:
        model = Team
        fields = ('id', 'title', 'team_lead')
        import_id_fields = ('id',)


class CustomUserResource(resources.ModelResource):
    team = fields.Field(
        column_name='team',
        attribute='team',
        widget=ForeignKeyWidget(Team, 'title')
    )

    class Meta:
        model = CustomUser
        fields = (
            'id',
            'username',
            'full_name',
            'role',
            'team',
            'email',
            'is_active',
            'is_staff'
        )
        import_id_fields = ('username',)

    def before_save_instance(self, instance, using_transactions, dry_run):
        """
        Force password for every imported user
        """
        instance.set_password("Smart@123")

        
class ProjectResource(resources.ModelResource):
    created_by = fields.Field(
        column_name='created_by',
        attribute='created_by',
        widget=ForeignKeyWidget(CustomUser, 'username')
    )

    class Meta:
        model = Project
        fields = (
            'id',
            'name',
            'description',
            'is_active',
            'is_public',
            'created_by'
        )
        import_id_fields = ('name',)
