import pyodbc
import os

# Configuration
server = 'your_server_name'
database = 'your_database_name'
username = 'your_username'
password = 'your_password'
output_file = 'export_users.sql'

# Connect to the SQL Server
def connect_to_sql_server():
    connection_string = f"DRIVER={{SQL Server}};SERVER={server};DATABASE={database};UID={username};PWD={password}"
    return pyodbc.connect(connection_string)

# Query to retrieve database users and permissions
def get_users_and_permissions(cursor):
    query = """
    SELECT dp.name AS user_name, dp.type_desc, dp.create_date, dp.modify_date,
           p.permission_name, p.state_desc, o.name AS object_name
    FROM sys.database_principals dp
    LEFT JOIN sys.database_permissions p ON dp.principal_id = p.grantee_principal_id
    LEFT JOIN sys.objects o ON p.major_id = o.object_id
    WHERE dp.type IN ('S', 'U', 'G') -- SQL user, Windows user, Windows group
      AND dp.name NOT IN ('dbo', 'guest', 'sys', 'INFORMATION_SCHEMA')
    ORDER BY dp.name;
    """
    cursor.execute(query)
    return cursor.fetchall()

# Generate SQL script for users and permissions
def generate_sql_script(users_permissions):
    script_lines = []

    current_user = None
    for row in users_permissions:
        user_name, type_desc, create_date, modify_date, permission_name, state_desc, object_name = row

        if user_name != current_user:
            if current_user:
                script_lines.append("\n")
            script_lines.append(f"-- User: {user_name}\n")
            script_lines.append(f"CREATE USER [{user_name}];\n")
            current_user = user_name

        if permission_name:
            object_clause = f" ON [{object_name}]" if object_name else ""
            script_lines.append(f"GRANT {permission_name} TO [{user_name}]{object_clause};\n")

    return script_lines

# Write the script to a file
def write_to_file(script_lines, file_path):
    with open(file_path, 'w') as file:
        file.writelines(script_lines)

# Main function
def main():
    try:
        print("Connecting to the database...")
        connection = connect_to_sql_server()
        cursor = connection.cursor()

        print("Fetching users and permissions...")
        users_permissions = get_users_and_permissions(cursor)

        print("Generating SQL script...")
        script_lines = generate_sql_script(users_permissions)

        print(f"Writing to file: {output_file}")
        write_to_file(script_lines, output_file)

        print(f"SQL script has been exported to {os.path.abspath(output_file)}")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if 'connection' in locals():
            connection.close()

if __name__ == "__main__":
    main()
