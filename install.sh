#!/bin/bash

################################################################################
# Variables you should adjust for your setup
################################################################################

APPHOST=12.34.56.78
SERVICENAME=meteor_app

################################################################################
# Internal variables
################################################################################

MAINUSER=$(whoami)
MAINGROUP=$(id -g -n $MAINUSER)

GITBAREREPO=/home/$MAINUSER/$SERVICENAME.git
EXPORTFOLDER=/tmp/$SERVICENAME

APPFOLDER=/home/$MAINUSER/$SERVICENAME
APPBINFOLDER=$APPFOLDER/bin
APPENV=$APPFOLDER/env.sh
APPCONFIGBASE=$APPFOLDER/config

################################################################################
# Utility functions
################################################################################

function replace {
	sudo perl -0777 -pi -e "s{\Q$2\E}{$3}gm" "$1"
}

function replace_noescape {
	sudo perl -0777 -pi -e "s{$2}{$3}gm" "$1"
}

function symlink {
	if [ ! -f $2 ]
		then
			sudo ln -s "$1" "$2"
	fi
}

function append {
	echo -e "$2" | sudo tee -a "$1" > /dev/null
}

################################################################################
# Task functions
################################################################################

function apt_update_upgrade {
	echo "--------------------------------------------------------------------------------"
	echo "Update and upgrade all packages"
	echo "--------------------------------------------------------------------------------"

	sudo apt-get -y update
	sudo apt-get -y upgrade
}

function install_fail2ban {
	echo "--------------------------------------------------------------------------------"
	echo "Install fail2ban"
	echo "--------------------------------------------------------------------------------"

	# Reference: http://plusbryan.com/my-first-5-minutes-on-a-server-or-essential-security-for-linux-servers
	sudo apt-get -y install fail2ban
}

function configure_firewall {
	echo "--------------------------------------------------------------------------------"
	echo "Configure firewall"
	echo "--------------------------------------------------------------------------------"

	# Reference: http://plusbryan.com/my-first-5-minutes-on-a-server-or-essential-security-for-linux-servers
	sudo ufw allow 22
	sudo ufw allow 80
	sudo ufw allow 443
}

function configure_automatic_security_updates {
	echo "--------------------------------------------------------------------------------"
	echo "Configure automatic security updates"
	echo "--------------------------------------------------------------------------------"

	# Reference: http://plusbryan.com/my-first-5-minutes-on-a-server-or-essential-security-for-linux-servers

	# Note that you will still need to do your own restarts. Uncomment this line if you
	# would like to have your server restarted automatically at 11:59pm on Sundays:
	#append "/etc/crontab" "59 23\t* * 7\troot\t/sbin/shutdown -r now >> /dev/null 2>&1"

	sudo apt-get -y install unattended-upgrades

	replace "/etc/apt/apt.conf.d/10periodic" \
'APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";' \
'APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";'
}

function install_git {
	echo "--------------------------------------------------------------------------------"
	echo "Install Git"
	echo "--------------------------------------------------------------------------------"

	sudo apt-get -y install git-core
	sudo git config --system user.email "$MAINUSER@$APPHOST"
	sudo git config --system user.name "$MAINUSER"
}

function install_nodejs {
	echo "--------------------------------------------------------------------------------"
	echo "Install Node.js"
	echo "--------------------------------------------------------------------------------"

	sudo apt-get -y install python-software-properties
	sudo add-apt-repository -y ppa:chris-lea/node.js
	sudo apt-get -y update
	sudo apt-get -y install nodejs
}

function install_mongodb {
	echo "--------------------------------------------------------------------------------"
	echo "Install MongoDB"
	echo "--------------------------------------------------------------------------------"

	sudo apt-get -y install mongodb
}

function install_meteor {
	echo "--------------------------------------------------------------------------------"
	echo "Install Meteor"
	echo "--------------------------------------------------------------------------------"

	curl https://install.meteor.com | /bin/sh
}

function install_meteorite {
	echo "--------------------------------------------------------------------------------"
	echo "Install Meteorite"
	echo "--------------------------------------------------------------------------------"

	sudo -H npm install meteorite -g
}

function install_phantomjs {
	echo "--------------------------------------------------------------------------------"
	echo "Install PhantomJS"
	echo "--------------------------------------------------------------------------------"

	sudo apt-get -y install fontconfig
	sudo npm install phantomjs -g
}

function setup_app_skeleton {
	echo "--------------------------------------------------------------------------------"
	echo "Setup app skeleton"
	echo "--------------------------------------------------------------------------------"

	rm -rf $APPFOLDER
	mkdir -p $APPBINFOLDER
	touch $APPBINFOLDER/main.js
}

function setup_app_service {
	echo "--------------------------------------------------------------------------------"
	echo "Setup app service"
	echo "--------------------------------------------------------------------------------"

	local SERVICEFILE=/etc/init/$SERVICENAME.conf
	local LOGFILE=/var/log/$SERVICENAME.log

	sudo rm -f $SERVICEFILE

	append $SERVICEFILE "description \"$SERVICENAME\""
	append $SERVICEFILE "author      \"Mathieu Bouchard <matb33@gmail.com>\""

	append $SERVICEFILE "start on runlevel [2345]"
	append $SERVICEFILE "stop on restart"
	append $SERVICEFILE "respawn"

	append $SERVICEFILE "pre-start script"
	append $SERVICEFILE "  echo \"[\$(/bin/date -u +%Y-%m-%dT%T.%3NZ)] (sys) Starting\" >> $LOGFILE"
	append $SERVICEFILE "end script"

	append $SERVICEFILE "pre-stop script"
	append $SERVICEFILE "  rm -f /var/run/$SERVICENAME.pid"
	append $SERVICEFILE "  echo \"[$(/bin/date -u +%Y-%m-%dT%T.%3NZ)] (sys) Stopping\" >> $LOGFILE"
	append $SERVICEFILE "end script"

	append $SERVICEFILE "script"
	append $SERVICEFILE "  sleep 5"
	append $SERVICEFILE "  echo \$\$ > /var/run/$SERVICENAME.pid"
	append $SERVICEFILE "  exec bash -c 'cd $APPFOLDER && source $APPENV && exec /usr/bin/node $APPBINFOLDER/main.js >> \"$LOGFILE\" 2>&1'"
	append $SERVICEFILE "end script"
}

function setup_bare_repo {
	echo "--------------------------------------------------------------------------------"
	echo "Setup bare repo"
	echo "--------------------------------------------------------------------------------"

	rm -rf $GITBAREREPO
	mkdir -p $GITBAREREPO
	cd $GITBAREREPO

	git init --bare
	git update-server-info
}

function setup_post_update_hook {
	echo "--------------------------------------------------------------------------------"
	echo "Setup post update hook"
	echo "--------------------------------------------------------------------------------"

	local HOOK=$GITBAREREPO/hooks/post-receive
	local RSYNCSOURCE=$EXPORTFOLDER/app_rsync

	rm -f $HOOK

	append $HOOK "#!/bin/bash"
	append $HOOK "unset \$(git rev-parse --local-env-vars)"

	append $HOOK "echo \"------------------------------------------------------------------------\""
	append $HOOK "echo \"Exporting app from git repo\""
	append $HOOK "echo \"------------------------------------------------------------------------\""
	append $HOOK "sudo rm -rf $EXPORTFOLDER"
	append $HOOK "mkdir -p $EXPORTFOLDER"
	append $HOOK "while read oldrev newrev refname"
	append $HOOK "do"
	append $HOOK "  BRANCH=\$(git rev-parse --symbolic --abbrev-ref \$refname)"
	append $HOOK "  git clone --recursive \"\$PWD\" -b \$BRANCH $EXPORTFOLDER"
	append $HOOK "  rm -rf $EXPORTFOLDER/.git*"
	append $HOOK "done"

	append $HOOK "echo \"------------------------------------------------------------------------\""
	append $HOOK "echo \"Updating environment variable files\""
	append $HOOK "echo \"------------------------------------------------------------------------\""
	append $HOOK "mkdir -p $APPCONFIGBASE/\$BRANCH"
	append $HOOK "cp -f $EXPORTFOLDER/config/\$BRANCH/env.sh $APPENV"
	append $HOOK "cp -f $EXPORTFOLDER/config/\$BRANCH/settings.json $APPCONFIGBASE/\$BRANCH/settings.json"

	append $HOOK "echo \"------------------------------------------------------------------------\""
	append $HOOK "echo \"Bundling app as a standalone Node.js app\""
	append $HOOK "echo \"------------------------------------------------------------------------\""
	append $HOOK "mkdir -p $RSYNCSOURCE"
	append $HOOK "cd $EXPORTFOLDER"
	append $HOOK "if [ -f $EXPORTFOLDER/smart.json ]; then"
	append $HOOK "  mrt build --directory $RSYNCSOURCE"
	append $HOOK "else"
	append $HOOK "  meteor build --directory $RSYNCSOURCE"
	append $HOOK "fi"
	append $HOOK "if [ -f $RSYNCSOURCE/bundle/main.js ]; then"
	append $HOOK "  echo \"------------------------------------------------------------------------\""
	append $HOOK "  echo \"Adjust bundle permissions\""
	append $HOOK "  echo \"------------------------------------------------------------------------\""
	append $HOOK "  sudo find \"$RSYNCSOURCE/bundle\" -type f -exec chmod 644 {} +;"
	append $HOOK "  sudo find \"$RSYNCSOURCE/bundle\" -type d -exec chmod 755 {} +;"

	append $HOOK "  echo \"------------------------------------------------------------------------\""
	append $HOOK "  echo \"Run npm install\""
	append $HOOK "  echo \"------------------------------------------------------------------------\""
	append $HOOK "  (cd $RSYNCSOURCE/bundle/programs/server && npm install)"

	append $HOOK "  echo \"------------------------------------------------------------------------\""
	append $HOOK "  echo \"Rsync standalone app to active app location\""
	append $HOOK "  echo \"------------------------------------------------------------------------\""
	append $HOOK "  rsync --checksum --recursive --update --delete --times $RSYNCSOURCE/bundle/ $APPBINFOLDER/"

	append $HOOK "  echo \"------------------------------------------------------------------------\""
	append $HOOK "  echo \"Restart app\""
	append $HOOK "  echo \"------------------------------------------------------------------------\""
	append $HOOK "  sudo service $SERVICENAME restart"

	# Clean-up
	append $HOOK "  cd $APPBINFOLDER"
	append $HOOK "  sudo rm -rf $EXPORTFOLDER"

	append $HOOK "else"
	append $HOOK "  echo \"Oops... couldn't find main.js\""
	append $HOOK "fi"

	append $HOOK "echo \"\n\n--- Done.\""

	sudo chown $MAINUSER:$MAINGROUP $HOOK
	chmod +x $HOOK
}

function show_conclusion {
	echo -e "\n\n\n\n\n"
	echo "########################################################################"
	echo " On your local development server"
	echo "########################################################################"
	echo ""
	echo "Add remote repository:"
	echo "$ git remote add ec2 $MAINUSER@$APPHOST:$SERVICENAME.git"
	echo ""
	echo "Add to your ~/.ssh/config:"
	echo -e "Host $APPHOST\n  IdentityFile PRIVATE_KEY_YOU_GOT_FROM_AWS.pem"
	echo ""
	echo "To deploy:"
	echo "$ git push ec2 master"
	echo ""
	echo "########################################################################"
	echo " Manual commands to run to finish off installation"
	echo "########################################################################"
	echo ""
	echo "Run the following command:"
	echo "$ sudo ufw enable"
	echo ""
	echo "Reboot to complete the installation. Example:"
	echo "$ sudo reboot"
	echo ""
}

################################################################################

apt_update_upgrade
install_fail2ban
configure_firewall
configure_automatic_security_updates
install_git
install_nodejs
install_mongodb
install_meteor
install_meteorite
install_phantomjs
setup_app_skeleton
setup_app_service
setup_bare_repo
setup_post_update_hook
show_conclusion