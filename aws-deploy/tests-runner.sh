
#!/bin/bash

until test-manager.sh $@; do
    echo "test-manager.sh crashed with exit code $?.  Respawning.." >&2
    sleep 1
done
