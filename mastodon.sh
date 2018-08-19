#!/bin/bash
set -eux

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"  && pwd )"
PERL='docker run --rm -i perl:5-slim perl'
ALPINE="alpine:3.8"

source $BASEDIR/.env

docker run --rm -i perl:5-slim perl -E ''
docker run --rm $ALPINE test true

if [ -n ${DOCKER_COMPOSE_CONTAINER_VERSION:-} ]; then
	DOCKER_COMPOSE='docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v '$BASEDIR':/rootfs'$BASEDIR' -w=/rootfs'$BASEDIR' docker/compose:'$DOCKER_COMPOSE_CONTAINER_VERSION
else
	DOCKER_COMPOSE='docker-compose'
fi

cd $BASEDIR

function do_create_volumes {
	for i in postgres redis assets packs system; do
		local volname=$COMPOSE_PROJECT_NAME'-'$i
		echo -n "create named volume: "
		docker volume create $volname
	done

	MUID=$( $DOCKER_COMPOSE run --rm web id -u | $PERL -npe 's/\r//g' )
	MGID=$( $DOCKER_COMPOSE run --rm web id -g | $PERL -npe 's/\r//g' )

	docker run --rm -i \
		-v $COMPOSE_PROJECT_NAME'-assets:/m/assets' \
		-v $COMPOSE_PROJECT_NAME'-packs:/m/packs' \
		-v $COMPOSE_PROJECT_NAME'-system:/m/system' \
		$ALPINE chown -v -R $MUID:$MGID /m

}

function do_remove_volumes {
	for i in postgres redis assets packs system; do
		local volname=$COMPOSE_PROJECT_NAME'-'$i
		echo -n "remove named volume: "
		docker volume rm $volname || true
	done
}


function do_create {
	rm -rf  mstdn-revert-enforce-https/assets
	mkdir -p mstdn-revert-enforce-https/assets

	if [ ! -e .env.production.sample ]; then
		curl https://raw.githubusercontent.com/tootsuite/mastodon/$MSTDN_VER/.env.production.sample > .env.production.sample
	fi

	cp -f  .env.production.sample .env.production

	$DOCKER_COMPOSE build
	$DOCKER_COMPOSE pull

	do_create_volumes
	$DOCKER_COMPOSE run --rm web rake --version

	cp -f .env.production.sample .env.production

	cat >> .env.production << 'EOS'
LOCAL_DOMAIN=127.0.0.1:3000
LOCAL_HTTPS=false
RAILS_ENV=production

SMTP_SERVER=mailcatcher
SMTP_PORT=1025
SMTP_LOGIN=
SMTP_PASSWORD=
SMTP_FROM_ADDRESS=notifications@localhost
SMTP_AUTH_METHOD=none

EOS

	local SECRET_KEY_BASE=$( $DOCKER_COMPOSE run --rm web rake secret | $PERL -npe 's/\r//g' )
	local OTP_SECRET=$( $DOCKER_COMPOSE run --rm web rake secret | $PERL -npe 's/\r//g' )

	cat .env.production | $PERL -pE " \
		s/^SECRET_KEY_BASE=/SECRET_KEY_BASE=$SECRET_KEY_BASE/m; \
		s/^OTP_SECRET=/OTP_SECRET=$OTP_SECRET/m \
	" > .env.production.tmp
	mv -f .env.production.tmp .env.production

	eval $( $DOCKER_COMPOSE run --rm web rake mastodon:webpush:generate_vapid_key | $PERL -npe 's/\r//sg; s/^(.+)/local $1/mg' )

	cat .env.production | $PERL -pE " \
		s/^VAPID_PRIVATE_KEY=/VAPID_PRIVATE_KEY=$VAPID_PRIVATE_KEY/m; \
		s/^VAPID_PUBLIC_KEY=/VAPID_PUBLIC_KEY=$VAPID_PUBLIC_KEY/m \
	" > .env.production.tmp
	mv -f .env.production.tmp .env.production

}

function do_init {
	$DOCKER_COMPOSE run --rm web rails db:setup SAFETY_ASSURED=1
	$DOCKER_COMPOSE run --rm web rails assets:precompile
}

do_backup() {

	if [ -z $(docker ps -q -f "id=$($DOCKER_COMPOSE ps -q db)" -f "status=running") ]; then
		echo "database not working."
		exit 1
	fi

	rm -rf var/backup
	mkdir -p var/backup

	$DOCKER_COMPOSE exec db pg_dump -U postgres postgres > var/backup/mastodon.sql

	for i in assets packs system; do
		docker run --rm -i -v $COMPOSE_PROJECT_NAME'-'$i:/m/$i \
			$ALPINE tar cvC /m $i > var/backup/$i.tar
	done

	cp -vf .env.production var/backup

}

do_restore() {

	$DOCKER_COMPOSE up -d db
	DB_CTNR=$(docker ps -q -f "id=$($DOCKER_COMPOSE ps -q db)" -f "status=running")
	cat var/backup/mastodon.sql | docker exec -i $DB_CTNR psql -U postgres

	MUID=$( $DOCKER_COMPOSE run --rm web id -u | $PERL -npe 's/\r//g' )
	MGID=$( $DOCKER_COMPOSE run --rm web id -g | $PERL -npe 's/\r//g' )

	for i in assets packs system; do
		cat var/backup/$i.tar | \
			docker run --rm -i -v $COMPOSE_PROJECT_NAME'-'$i:/m/$i \
			$ALPINE sh -c "tar xvC /m; chown -R $MUID:$MGID /m/$i"
	done

	cp -vf var/backup/.env.production .

}


function do_destroy {
	if [ -e .env.production ]; then
		$DOCKER_COMPOSE down || true
	fi
	sleep 1
	do_remove_volumes
}


case "${1:-}" in

	"create"  )
		do_destroy
		do_create
		do_init
		$DOCKER_COMPOSE up -d
		echo " *** SUCCESS ***"
		;;

	"restore" )
		do_destroy
		do_create
		do_restore
		$DOCKER_COMPOSE up -d
		echo " *** SUCCESS ***"
		;;

	"backup" )
		do_backup
		$DOCKER_COMPOSE up -d
		echo " *** SUCCESS ***"
		;;

	"destroy" )
		do_destroy
		echo " *** SUCCESS ***"
		;;

	"up" )
		exec $DOCKER_COMPOSE up -d
		;;

	"down" )
		exec $DOCKER_COMPOSE down
		;;

	"shell" )
		exec $DOCKER_COMPOSE exec web sh
		;;

	"psql" )
		exec $DOCKER_COMPOSE exec db psql -U postgres postgres
		;;

	"rails" )
		shift
		exec $DOCKER_COMPOSE exec web rails $@
		;;

	"logs" )
		exec $DOCKER_COMPOSE logs -f
		;;

	*  )
		echo "USAGE:"
	   	echo "  $0 [ create | destroy ]"
	   	echo "  $0 [ backup | restore ]"
	   	echo "  $0 [ up | down ]"
	   	echo "  $0 [ shell | psql | logs ]"
	   	echo "  $0 rails [rails commands]"
		exit 1
		;;

esac

