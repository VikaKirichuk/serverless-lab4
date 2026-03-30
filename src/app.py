import json
import boto3
import os
import uuid
import psycopg2
import psycopg2.extras
from datetime import datetime

DB_HOST     = os.environ.get("DB_HOST")
DB_PORT     = os.environ.get("DB_PORT", "5432")
DB_NAME     = os.environ.get("DB_NAME")
DB_USER     = os.environ.get("DB_USER")
DB_PASSWORD = os.environ.get("DB_PASSWORD")
LOG_BUCKET  = os.environ.get("LOG_BUCKET")

s3 = boto3.client("s3")


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=int(DB_PORT),
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=5,
        cursor_factory=psycopg2.extras.RealDictCursor
    )


def ensure_table(cursor):
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS students (
            id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name       VARCHAR(255) NOT NULL,
            group_name VARCHAR(50)  NOT NULL,
            email      VARCHAR(255)
        )
    """)


def write_log(action, details):
    if not LOG_BUCKET:
        return
    log_entry = {
        "timestamp": datetime.utcnow().isoformat(),
        "action":    action,
        "details":   details
    }
    key = f"logs/{datetime.utcnow().strftime('%Y/%m/%d')}/{uuid.uuid4()}.json"
    s3.put_object(
        Bucket=LOG_BUCKET,
        Key=key,
        Body=json.dumps(log_entry, ensure_ascii=False),
        ContentType="application/json"
    )


def handler(event, context):
    try:
        http_method = event["requestContext"]["http"]["method"]
        params      = event.get("queryStringParameters") or {}

        conn = get_connection()
        conn.autocommit = False

        try:
            with conn.cursor() as cur:
                ensure_table(cur)

                # POST /students
                if http_method == "POST":
                    body  = json.loads(event.get("body") or "{}")
                    name  = body.get("name", "").strip()
                    group = body.get("group", "").strip()
                    email = body.get("email", "").strip() or None

                    if not name or not group:
                        return _resp(400, {"message": "Fields 'name' and 'group' are required"})

                    cur.execute(
                        "INSERT INTO students (name, group_name, email) VALUES (%s, %s, %s) RETURNING *",
                        (name, group, email)
                    )
                    student = dict(cur.fetchone())
                    student["id"] = str(student["id"])
                    conn.commit()

                    write_log("POST /students", {"id": student["id"], "name": name})
                    return _resp(201, student)

                # GET /students?group=
                elif http_method == "GET":
                    group_filter = params.get("group")

                    if group_filter:
                        cur.execute(
                            "SELECT * FROM students WHERE group_name = %s ORDER BY name",
                            (group_filter,)
                        )
                    else:
                        cur.execute("SELECT * FROM students ORDER BY name")

                    rows = [dict(r) for r in cur.fetchall()]
                    for r in rows:
                        r["id"] = str(r["id"])
                    conn.commit()

                    write_log("GET /students", {"group_filter": group_filter, "count": len(rows)})
                    return _resp(200, {"students": rows})

                # DELETE /students/{id}
                elif http_method == "DELETE":
                    path = event.get("rawPath", "")
                    sid  = path.rstrip("/").split("/")[-1]

                    cur.execute(
                        "DELETE FROM students WHERE id = %s::uuid RETURNING id",
                        (sid,)
                    )
                    if not cur.fetchone():
                        conn.rollback()
                        return _resp(404, {"message": "Student not found"})

                    conn.commit()
                    write_log("DELETE /students", {"id": sid})
                    return _resp(204, None)

                else:
                    return _resp(405, {"message": "Method Not Allowed"})

        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    except Exception as e:
        print(f"Error: {e}")
        try:
            write_log("ERROR", {"error": str(e)})
        except Exception:
            pass
        return _resp(500, {"message": "Internal Server Error"})


def _resp(status, body):
    r = {"statusCode": status, "headers": {"Content-Type": "application/json"}}
    if body is not None:
        r["body"] = json.dumps(body, default=str, ensure_ascii=False)
    return r