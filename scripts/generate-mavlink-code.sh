mkdir -p src/Mavlink
sudo docker run --rm --user "$(id -u):$(id -g)" \
  --volume "$PWD/src/Mavlink":/out python:3.13-slim sh -c '
    pip install -q --no-cache-dir --target /tmp/pm pymavlink &&
    PYTHONPATH=/tmp/pm python -m pymavlink.tools.mavgen --lang=CS --wire-protocol=2.0 \
      -o /out /tmp/pm/pymavlink/dialects/v20/ardupilotmega.xml'