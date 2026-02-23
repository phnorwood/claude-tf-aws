### refresh website with latest content from repo.

/opt/homebrew/bin/ansible webservers -i ansible/inventory.ini -b \
  -m git -a "repo=https://github.com/phnorwood/phnorwood.com.git dest=/tmp/website-repo clone=yes update=yes force=yes"

/opt/homebrew/bin/ansible webservers -i ansible/inventory.ini -b \
  -m shell -a "cp -r /tmp/website-repo/* /var/www/html/ && rm -rf /tmp/website-repo"

/opt/homebrew/bin/ansible-playbook --inventory ansible/inventory.ini ansible/build-jekyll.yml
