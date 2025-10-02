# 🐳 Docker CLI Cheatsheet

## 🔹 Container Management
- **List running containers**
  docker ps

- **List all containers (including stopped)**
  docker ps -a

- **Start / Stop / Restart a container**
  docker start <container_name>
  docker stop <container_name>
  docker restart <container_name>

- **Remove a container**
  docker rm <container_name>

- **Jump inside a container shell**
  docker exec -it <container_name> bash
  # or use sh if bash isn't installed

## 🔹 Logs & Debugging
- **View container logs**
  docker logs <container_name>

- **Follow logs (like tail -f)**
  docker logs -f <container_name>

- **Inspect container details (env, mounts, IPs, etc.)**
  docker inspect <container_name>

## 🔹 Images
- **List images**
  docker images

- **Pull image from registry**
  docker pull <image_name>:tag

- **Remove image**
  docker rmi <image_id>

## 🔹 Networks
- **List networks**
  docker network ls

- **Create custom bridge network**
  docker network create mynet

- **Run container attached to custom network**
  docker run -d --name test --network mynet nginx

## 🔹 Volumes
- **List volumes**
  docker volume ls

- **Create a named volume**
  docker volume create mydata

- **Remove unused volumes**
  docker volume prune

## 🔹 Housekeeping
- **Stop & remove all containers**
  docker stop $(docker ps -aq)
  docker rm $(docker ps -aq)

- **Remove dangling (unused) images**
  docker image prune

- **Remove everything not used**
  docker system prune -a

---

✅ Tip: Use **Portainer** for a GUI overview of all the above.