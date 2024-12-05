* Required for htpasswd
    sudo apt install apache2-utils -y

* get your password and base64
    htpasswd -Bc htpasswd registry
    echo username:password | base64
