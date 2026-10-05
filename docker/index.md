# Docker lab

Hello dear student.

This lab runs a few Docker commands on a machine where Docker is already installed. It is a short check of those commands, not a Docker course.

## What is running

`docker ps` lists containers that are running right now.

Try it:

```shell
docker ps
```

The list should be empty. Nothing has been started yet.

## Start a web server

Run nginx in a container named `web`. Docker downloads the `nginx` image over the network when this machine does not already have it. `-d` leaves the container running after the command returns. `-p 8080:80` publishes its port 80 on port 8080 of this machine.

```shell
docker run -d --name web -p 8080:80 nginx
```

## Look again

```shell
docker ps
```

The list should include a container named `web`. It stays there until you stop it.

## Fetch its page

`curl` asks the server for its front page. This address is the machine you are logged into, on the port published above.

```shell
curl http://127.0.0.1:8080/
```

The reply is nginx's welcome page.

## Stop it

```shell
docker stop web
```

`docker ps` no longer lists it. Docker still remembers the container until you remove it:

```shell
docker rm web
```

## Summary

In this lab, we covered a short pass over one container:

- `docker ps` for listing running containers
- `docker run -d` to start nginx and leave it running
- `curl` to fetch the page it serves
- `docker stop` and `docker rm` to remove it

The `nginx` image was downloaded by `docker run`. Dockerfiles are left for later.

Congratulations on completing this lab.
