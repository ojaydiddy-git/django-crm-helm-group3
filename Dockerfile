FROM python:3.13-alpine

WORKDIR /app

COPY django-crm/requirements.txt .

# Runtime lib for mysqlclient (leave installed)
RUN apk add --no-cache mariadb-connector-c

# Build deps -> install -> remove
RUN apk add --no-cache --virtual .build-deps gcc musl-dev mariadb-dev \
 && pip install --no-cache-dir -r requirements.txt \
 && apk del .build-deps

# App code
COPY django-crm .
COPY settings.py /app/webcrm/settings.py

# Tell Django we’re mounted under /proxy/8080
ENV SCRIPT_NAME=/proxy/8080

# Run plain devserver
CMD ["sh", "-c", "python manage.py migrate && python manage.py runserver 0.0.0.0:8080 --noreload"]
