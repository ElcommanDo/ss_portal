import sqlite3

# Verify this filename is exactly what is in your settings.py
db_path = 'db_test.sqlite3' 
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print(f"Connecting to {db_path}...")

# 1. DROP the "New" tables that might be blocking the migration
new_tables = ['app_kpicategory', 'app_employeekpi', 'app_kpifeedback', 'app_kpitemplate']
for table in new_tables:
    cursor.execute(f"DROP TABLE IF EXISTS {table};")
    print(f"Cleared potential duplicate: {table}")

# 2. CREATE "Dummy" tables that the migration wants to ALTER/DELETE
# Migration 0020 wants to remove fields from these, so they MUST exist
print("Creating dummy legacy tables...")
cursor.execute("CREATE TABLE IF NOT EXISTS app_kpilog (id integer PRIMARY KEY, admin_actor_id integer, employee_id integer, kpi_id integer);")
cursor.execute("CREATE TABLE IF NOT EXISTS app_kpi (id integer PRIMARY KEY);")
cursor.execute("CREATE TABLE IF NOT EXISTS app_employeekpiscore (id integer PRIMARY KEY);")

# 3. CLEAN Migration History
cursor.execute("DELETE FROM django_migrations WHERE app='app' AND name='0020_auto_20260308_2117';")
print("Reset migration 0020 record.")

conn.commit()
conn.close()
print("\nEnvironment ready. Run: python manage.py migrate app")