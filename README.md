# django-crm-helm
django crm from docker compose to helm chart

To run this with `docker compose`:

1. Edit the file patch-settings.diff to have your hostname and url:

```diff
 # Add your hosts to the list.
-ALLOWED_HOSTS = ['localhost', '127.0.0.1']
-
+ALLOWED_HOSTS = ['localhost', '127.0.0.1', 'codespace-dev.k3p.dev']
+CSRF_TRUSTED_ORIGINS=['https://codespace-dev.k3p.dev']

```

```bash
cp django-crm/webcrm/settings.py .
patch <patch-settings.diff
ansible-playbook up.yml
```

This will create the database. The first time you run this you will need to create a super user account.

```bash
docker compose exec crm sh -c "python manage.py setupdata"
```

This will display a super user name and password. Save this somewhere as it can't be re-retrieved. The admin interface will be at `/en/456-admin/` and the regular at `/en/123`.

## Marks

Part 1. Create a repository on one of your gitea(s) by cloning [this repository](https://github.com/rhildred/django-crm-helm), (or atomic crm, if you have it working already). Add your teammates as collaborators (4 marks)

Part 2. Use one student's truenas for nfs storage for your database. You can use [this article](https://www.dontpanicblog.co.uk/2024/12/20/nfs-shares-in-docker/) to help (4 marks)

Part 3. Create a jenkinsfile or gitea action that updates the image from the included Dockerfile on your gitea docker image repository (see [this article](https://docs.gitea.com/usage/packages/container)) every time code is pushed (4 marks)

Part 4. Use a cloudflared ingress to expose your crm from your cluster to the internet (4 marks)

Part 5. Consume the docker image from step 3 in your docker-compose.yml, use Kompose to create a helm chart and modify up.yaml and down.yaml to run your image on kubernetes and expose it with a cloudflared tunnel (4 marks).

Total. 20

I hope that this works better than what I had before. Notice that I started with the mysql setup that you are used to from PROG8850. Hopefully the docker-compose.yml file will take you from working code to working code!

======================================================================
READ ME
======================================================================

Imported the starter repo into our Gitea:

git clone https://github.com/rhildred/django-crm-helm.git django-crm-helm-group3
cd django-crm-helm-group3
git remote remove origin
git remote add origin https://gitea.ojaydiddy.site/gitea_admin/django-crm-helm-group3.git
git push -u origin main

=======================================================================
Added collaborators (Gitea UI → Repository → Settings → Collaborators → add teammates with Write).

========================================================================
Part 2 — Use TrueNAS NFS for MySQL data (4 marks)
=========================================================================

Goal: Put MySQL’s data directory on an NFS share hosted on a teammate’s TrueNAS.

What we did

Verified the export from TrueNAS (NFS server 10.172.27.15):

showmount -e 10.172.27.15
# Export: /mnt/application/class-crm-mysql

Mounted the share on the Docker host (Ubuntu):

sudo apt update && sudo apt install -y nfs-common
sudo mkdir -p /mnt/class-crm-mysql
sudo mount -t nfs -o nfsvers=4 10.172.27.15:/mnt/application/class-crm-mysql /mnt/class-crm-mysql
sudo sh -c 'echo "nfs ok" > /mnt/class-crm-mysql/health.txt'
ls -l /mnt/class-crm-mysql


Pointed Docker to NFS via a named volume in docker-compose.yml

services:
  db:
    image: mysql:8.0.43             # pin to 8.0.43 (see pitfall below)
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: Secret5555
      MYSQL_DATABASE: crm_db
      MYSQL_USER: crm_user
      MYSQL_PASSWORD: crmpass
    ports:
      - "3306:3306"
    volumes:
      - mysql_db_data:/var/lib/mysql

volumes:
  mysql_db_data:
    driver: local
    driver_opts:
      type: "nfs"
      o: "addr=10.172.27.15,nfsvers=4,rw"
      device: ":/mnt/application/class-crm-mysql"


Brought the stack up and verified DB access:

docker compose up -d
docker exec -it $(docker compose ps -q db) \
  mysql -uroot -pSecret5555 -e "SELECT VERSION();"

# app user + smoke test
docker exec -it $(docker compose ps -q db) \
  mysql -ucrm_user -pcrmpass -e \
  "CREATE TABLE IF NOT EXISTS crm_db.test (id INT); INSERT INTO crm_db.test VALUES (1); SELECT * FROM crm_db.test;"


===========================================================
Part 3 — Build & push image with Gitea Actions
=======================================================

Runner (self-hosted) setup on Ubuntu:

Installed Docker CE (official packages).

Registered Gitea Actions runner (containerized):

mkdir -p ~/.gitea_runner
docker run --rm -it -v ~/.gitea_runner:/data \
  -e GITEA_INSTANCE_URL="https://gitea.ojaydiddy.site" \
  -e GITEA_RUNNER_REGISTRATION_TOKEN="<REG_TOKEN>" \
  -e GITEA_RUNNER_NAME="ubuntu2204-runner" \
  -e GITEA_RUNNER_LABELS="self-hosted,docker,ubuntu-22.04" \
  gitea/act_runner:latest register --no-interactive

docker run -d --name gitea_runner --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/.gitea_runner:/data gitea/act_runner:latest

Workflow at .gitea/workflows/build-and-push.yml

name: Build & Push to Gitea Registry
on:
  push:
    branches: ["main"]
  workflow_dispatch: {}
jobs:
  build-and-push:
    runs-on: self-hosted
    env:
      IMAGE: gitea.ojaydiddy.site/gitea_admin/django-crm-helm-group3
    steps:
      - name: Checkout
        uses: https://github.com/actions/checkout@v4

      - name: Log in to Gitea Container Registry
        uses: https://github.com/docker/login-action@v3
        with:
          registry: gitea.ojaydiddy.site
          username: ${{ secrets.REGISTRY_USER }}
          password: ${{ secrets.REGISTRY_PASSWORD }}

      - name: Build & Push
        uses: https://github.com/docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE }}:latest
            ${{ env.IMAGE }}:${{ github.sha }}
          cache-from: type=registry,ref=${{ env.IMAGE }}:buildcache
          cache-to: type=registry,ref=${{ env.IMAGE }}:buildcache,mode=max

Triggered the workflow:

date > .ci-trigger && git add .ci-trigger && git commit -m "CI: trigger" && git push


============================================================
Part 4 — Cloudflared ingress from the cluster
============================================================

Goal: Expose the in-cluster CRM Service to the internet over a Cloudflare Tunnel

What we did

Kept existing Cloudflare cert 

Named tunnel & DNS hostname:

cloudflared tunnel create crm-tunnel
cloudflared tunnel list
export TUNNEL_ID=55fb8453-63a7-4c89-aca6-13e7eb040b31   # crm-tunnel
export HOSTNAME=crm-g3-k8s.ojaydiddy.site
cloudflared tunnel route dns --overwrite-dns "$TUNNEL_ID" "$HOSTNAME"
ls -l ~/.cloudflared/${TUNNEL_ID}.json   # creds file exists

Configure the cloudflared.yaml


=====================================================
Challenges faced and fixes:
====================================================
MySQL restart loop / upgrade error
Logs showed: Cannot upgrade from 80043 to 90400, because the NFS data dir had been initialized by MySQL 8.0.43, but the default latest MySQL image was 9.4.x.
Fix: Pin the image to mysql:8.0.43 (as above), then docker compose down && docker compose up -d.

Runner not picking up jobs: workflow used runs-on: ubuntu-latest by default.
Fix: set runs-on: self-hosted.

Registration kept failing (“instance address is empty”) due to line wrapping.
Fix: used env-var registration (single line) 

DNS route pointed to the wrong tunnel (hostname was mapped to gitea-tunnel).
Fix: cloudflared tunnel route dns --overwrite-dns "$TUNNEL_ID" "$HOSTNAME".

Empty $TUNNEL_ID caused ~/.cloudflared/.json error when creating the secret.
Fix: export the real ID from cloudflared tunnel list before creating the secret.

Accidentally pasted YAML into the shell and used > redirection with kubectl apply.
Fix: write YAML to a file first, then kubectl apply -f.