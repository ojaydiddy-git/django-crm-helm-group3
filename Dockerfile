# Pin is optional but recommended
FROM python:3.13-alpine

WORKDIR /app

COPY django-crm/requirements.txt .

# --- Runtime dependency (KEEP this installed) ---
# Provides /usr/lib/libmariadb.so.3 needed by mysqlclient/MySQLdb at runtime
RUN apk add --no-cache mariadb-connector-c

# --- Build deps (remove after pip install) ---
RUN apk add --no-cache --virtual .build-deps \
      gcc musl-dev mariadb-dev \
  && pip install --no-cache-dir -r requirements.txt \
  && apk del .build-deps

COPY django-crm .
COPY settings.py /app/webcrm/settings.py

CMD ["sh", "-c", "python manage.py migrate && python manage.py runserver 0.0.0.0:8080 --noreload"]
