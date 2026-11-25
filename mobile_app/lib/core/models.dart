// Plain data classes for the JSON returned by /api/v1/.
// Every parser is defensive: a missing field never crashes the UI.

double asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String asString(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();

bool asBool(dynamic v) => v == true || v == 1 || v == 'true';

DateTime? asDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((key, value) => MapEntry(key.toString(), value));
  return <String, dynamic>{};
}

List<dynamic> asList(dynamic v) => v is List ? v : const [];

class PageResult<T> {
  final int count;
  final int page;
  final int pages;
  final List<T> results;
  final Map<String, dynamic> raw;

  PageResult({required this.count, required this.page, required this.pages, required this.results, required this.raw});

  bool get hasMore => page < pages;

  static PageResult<R> parse<R>(dynamic json, R Function(Map<String, dynamic>) item) {
    final m = asMap(json);
    return PageResult<R>(
      count: asInt(m['count']),
      page: asInt(m['page']) == 0 ? 1 : asInt(m['page']),
      pages: asInt(m['pages']) == 0 ? 1 : asInt(m['pages']),
      results: asList(m['results']).map((e) => item(asMap(e))).toList(),
      raw: m,
    );
  }
}

class UserBrief {
  final int id;
  final String username;
  final String fullName;
  final String role;
  final String roleLabel;
  final String? team;

  UserBrief({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.roleLabel,
    this.team,
  });

  factory UserBrief.fromJson(Map<String, dynamic> j) => UserBrief(
        id: asInt(j['id']),
        username: asString(j['username']),
        fullName: asString(j['full_name'], asString(j['username'])),
        role: asString(j['role']),
        roleLabel: asString(j['role_label'], asString(j['role'])),
        team: j['team']?.toString(),
      );

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class AppUser extends UserBrief {
  final String? email;
  final bool isActive;
  final bool isStaff;
  final bool isSuperuser;
  final int? teamId;
  final DateTime? dateJoined;

  AppUser({
    required super.id,
    required super.username,
    required super.fullName,
    required super.role,
    required super.roleLabel,
    super.team,
    this.email,
    required this.isActive,
    required this.isStaff,
    required this.isSuperuser,
    this.teamId,
    this.dateJoined,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: asInt(j['id']),
        username: asString(j['username']),
        fullName: asString(j['full_name'], asString(j['username'])),
        role: asString(j['role']),
        roleLabel: asString(j['role_label'], asString(j['role'])),
        team: j['team']?.toString(),
        email: j['email']?.toString(),
        isActive: asBool(j['is_active']),
        isStaff: asBool(j['is_staff']),
        isSuperuser: asBool(j['is_superuser']),
        teamId: j['team_id'] == null ? null : asInt(j['team_id']),
        dateJoined: asDate(j['date_joined']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'role': role,
        'role_label': roleLabel,
        'team': team,
        'email': email,
        'is_active': isActive,
        'is_staff': isStaff,
        'is_superuser': isSuperuser,
        'team_id': teamId,
        'date_joined': dateJoined?.toIso8601String(),
      };
}

/// What the signed-in user may see / do. Computed by the server from the
/// same role rules the web portal uses.
class Capabilities {
  final bool staffDashboard;
  final bool reviewTimesheets;
  final bool reports;
  final bool manageUsers;
  final bool manageTeams;
  final bool projects;
  final bool addProjectCost;
  final bool assignMissions;
  final bool processVacations;
  final bool allVacations;

  const Capabilities({
    this.staffDashboard = false,
    this.reviewTimesheets = false,
    this.reports = false,
    this.manageUsers = false,
    this.manageTeams = false,
    this.projects = true,
    this.addProjectCost = false,
    this.assignMissions = false,
    this.processVacations = false,
    this.allVacations = false,
  });

  factory Capabilities.fromJson(Map<String, dynamic> j) => Capabilities(
        staffDashboard: asBool(j['staff_dashboard']),
        reviewTimesheets: asBool(j['review_timesheets']),
        reports: asBool(j['reports']),
        manageUsers: asBool(j['manage_users']),
        manageTeams: asBool(j['manage_teams']),
        projects: j['projects'] == null ? true : asBool(j['projects']),
        addProjectCost: asBool(j['add_project_cost']),
        assignMissions: asBool(j['assign_missions']),
        processVacations: asBool(j['process_vacations']),
        allVacations: asBool(j['all_vacations']),
      );

  Map<String, dynamic> toJson() => {
        'staff_dashboard': staffDashboard,
        'review_timesheets': reviewTimesheets,
        'reports': reports,
        'manage_users': manageUsers,
        'manage_teams': manageTeams,
        'projects': projects,
        'add_project_cost': addProjectCost,
        'assign_missions': assignMissions,
        'process_vacations': processVacations,
        'all_vacations': allVacations,
      };

  /// Managers / leaders / admins get the management navigation.
  bool get isManager => reviewTimesheets || reports;
}

class IdName {
  final int id;
  final String name;
  IdName(this.id, this.name);

  factory IdName.fromJson(Map<String, dynamic> j) =>
      IdName(asInt(j['id']), asString(j['name'], asString(j['title'])));
}

class ValueLabel {
  final String value;
  final String label;
  ValueLabel(this.value, this.label);
  factory ValueLabel.fromJson(Map<String, dynamic> j) => ValueLabel(asString(j['value']), asString(j['label']));
}

class MetaData {
  final List<ValueLabel> taskTypes;
  final List<IdName> entryProjects;
  final List<UserBrief> users;
  final List<IdName> teams;
  final List<IdName> projects;
  final List<UserBrief> assignableEmployees;
  final DateTime today;

  MetaData({
    required this.taskTypes,
    required this.entryProjects,
    required this.users,
    required this.teams,
    required this.projects,
    required this.assignableEmployees,
    required this.today,
  });

  factory MetaData.fromJson(Map<String, dynamic> j) => MetaData(
        taskTypes: asList(j['task_types']).map((e) => ValueLabel.fromJson(asMap(e))).toList(),
        entryProjects: asList(j['entry_projects']).map((e) => IdName.fromJson(asMap(e))).toList(),
        users: asList(j['users']).map((e) => UserBrief.fromJson(asMap(e))).toList(),
        teams: asList(j['teams']).map((e) => IdName.fromJson(asMap(e))).toList(),
        projects: asList(j['projects']).map((e) => IdName.fromJson(asMap(e))).toList(),
        assignableEmployees: asList(j['assignable_employees']).map((e) => UserBrief.fromJson(asMap(e))).toList(),
        today: asDate(j['today']) ?? DateTime.now(),
      );
}

class TimesheetEntry {
  final int id;
  final int? timesheetId;
  final UserBrief? user;
  final IdName? project;
  final String taskType;
  final String description;
  final double hours;
  final DateTime? workDate;
  final String status;
  final String statusLabel;
  final bool isScheduled;
  final String? timeStart;
  final String? timeEnd;
  final bool onsiteAbroad;
  final bool onsiteEgypt;

  TimesheetEntry({
    required this.id,
    this.timesheetId,
    this.user,
    this.project,
    required this.taskType,
    required this.description,
    required this.hours,
    this.workDate,
    required this.status,
    required this.statusLabel,
    required this.isScheduled,
    this.timeStart,
    this.timeEnd,
    required this.onsiteAbroad,
    required this.onsiteEgypt,
  });

  factory TimesheetEntry.fromJson(Map<String, dynamic> j) => TimesheetEntry(
        id: asInt(j['id']),
        timesheetId: j['timesheet_id'] == null ? null : asInt(j['timesheet_id']),
        user: j['user'] == null ? null : UserBrief.fromJson(asMap(j['user'])),
        project: j['project'] == null ? null : IdName.fromJson(asMap(j['project'])),
        taskType: asString(j['task_type']),
        description: asString(j['task_description']),
        hours: asDouble(j['hours']),
        workDate: asDate(j['work_date']),
        status: asString(j['status']),
        statusLabel: asString(j['status_label'], asString(j['status'])),
        isScheduled: asBool(j['is_scheduled']),
        timeStart: j['time_start']?.toString(),
        timeEnd: j['time_end']?.toString(),
        onsiteAbroad: asBool(j['onsite_abroad']),
        onsiteEgypt: asBool(j['onsite_egypt']),
      );
}

class DaySheet {
  final int id;
  final DateTime? date;
  final double totalHours;
  final int tasksCount;
  final String summaryStatus;
  final UserBrief? user;
  final double abroadHours;
  final List<String> projects;

  DaySheet({
    required this.id,
    this.date,
    required this.totalHours,
    required this.tasksCount,
    required this.summaryStatus,
    this.user,
    this.abroadHours = 0,
    this.projects = const [],
  });

  factory DaySheet.fromJson(Map<String, dynamic> j) => DaySheet(
        id: asInt(j['id']),
        date: asDate(j['date']),
        totalHours: asDouble(j['total_hours']),
        tasksCount: asInt(j['tasks_count']),
        summaryStatus: asString(j['summary_status']),
        user: j['user'] == null ? null : UserBrief.fromJson(asMap(j['user'])),
        abroadHours: asDouble(j['onsite_abroad_hours']),
        projects: asList(j['projects']).map((e) => e.toString()).toList(),
      );
}

class Mission {
  final int id;
  final String body;
  final String priority;
  final String status;
  final bool isTask;
  final IdName? project;
  final DateTime? deadline;
  final bool isOverdue;
  final DateTime? createdAt;
  final UserBrief? employee;
  final UserBrief? createdBy;

  Mission({
    required this.id,
    required this.body,
    required this.priority,
    required this.status,
    required this.isTask,
    this.project,
    this.deadline,
    required this.isOverdue,
    this.createdAt,
    this.employee,
    this.createdBy,
  });

  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
        id: asInt(j['id']),
        body: asString(j['body']),
        priority: asString(j['priority']),
        status: asString(j['status']),
        isTask: asBool(j['is_task']),
        project: j['project'] == null ? null : IdName.fromJson(asMap(j['project'])),
        deadline: asDate(j['deadline']),
        isOverdue: asBool(j['is_overdue']),
        createdAt: asDate(j['created_at']),
        employee: j['employee'] == null ? null : UserBrief.fromJson(asMap(j['employee'])),
        createdBy: j['created_by'] == null ? null : UserBrief.fromJson(asMap(j['created_by'])),
      );

  bool get isCompleted => status == 'completed';
}

class Vacation {
  final int id;
  final UserBrief? user;
  final DateTime? date;
  final int duration;
  final String reason;
  final String status;

  Vacation({required this.id, this.user, this.date, required this.duration, required this.reason, required this.status});

  factory Vacation.fromJson(Map<String, dynamic> j) => Vacation(
        id: asInt(j['id']),
        user: j['user'] == null ? null : UserBrief.fromJson(asMap(j['user'])),
        date: asDate(j['date']),
        duration: asInt(j['duration']),
        reason: asString(j['reason']),
        status: asString(j['status']),
      );
}

class ProjectInfo {
  final int id;
  final String name;
  final String description;
  final bool isActive;
  final bool isPublic;
  final String? createdBy;
  final double loggedHours;
  final int contributors;

  ProjectInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.isActive,
    required this.isPublic,
    this.createdBy,
    required this.loggedHours,
    required this.contributors,
  });

  factory ProjectInfo.fromJson(Map<String, dynamic> j) => ProjectInfo(
        id: asInt(j['id']),
        name: asString(j['name']),
        description: asString(j['description']),
        isActive: asBool(j['is_active']),
        isPublic: asBool(j['is_public']),
        createdBy: j['created_by']?.toString(),
        loggedHours: asDouble(j['logged_hours']),
        contributors: asInt(j['contributors']),
      );
}
