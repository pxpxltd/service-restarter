# Service Restarter

Simple bash script and supervisor config to run service restarts after deployments

## Requirements

- Linux
- Supervisor

## Installation

```
curl -s -o /tmp/install.sh https://raw.githubusercontent.com/pxpxltd/service-restarter/refs/heads/master/dist/install.sh; sudo bash /tmp/install.sh; rm -f /tmp/install.sh
```

Script will ask you for name and path. 

If you run it from app path it will be detected automatically. 