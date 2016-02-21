mkdir -p images
sed -n '/^ *#source/s/^ *#source *//gp' < docker-compose.yml | \
  while read repo ; do
    ( cd images ; git clone "$repo" )
  done
