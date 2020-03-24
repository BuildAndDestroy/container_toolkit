#!/bin/bash

#################################################
# Authenticate Users and Create Their Namespace #
#################################################

USER=$2

function check_user_input() {
    if [[ $USER == '' ]]; then
        echo '[*] Please provide a user name.'
        exit
    fi
}


function _run_as_root() { #  Run as root
    if [[ $(id -u) != 0 ]]; then
        echo 'Must be ran as root.'
        exit
    fi
}


function _help_menu() { #  Help menu
    echo '[*] Help Menu:'
    echo ''
    echo "[*] -u Authenticate a user, parse the user\'s name."
    echo '          bash authenticate_user.sh -a iamauser'
    echo ''
    echo '[*] -d Delete a RoleBind to revoke user access.'
    echo '          bash authenticate_user -d iamauser-admin'
    echo ''
    echo ''
    exit
}


function create_key_and_csr() { #  Generate key and csr for user
    echo '[*] Creating key and csr'
    openssl req -new -newkey rsa:4096 -nodes -keyout $USER-k8s.key -out $USER-k8s.csr -subj "/CN="$USER"/O=devops"
}


function kube_apply_csr_yaml() { #  Create yaml file to request CA approval and apply the yaml
    echo "[*] Applying the "$USER"-k8s-csr.yaml"
    users_base64_csr=$(cat $USER-k8s.csr | base64 | tr -d '\n')
    cat <<EOF > $USER-k8s-csr.yaml
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: $USER-k8s-access
spec:
  groups:
  - system:authenticated
  request: "$users_base64_csr"
  usages:
  - client auth
EOF
    kubectl create -f $USER-k8s-csr.yaml
}


function kube_get_csr() { #  Get the pending or approved csr waiting for CA approval
    echo '[*] Get csr from kubectl'
    kubectl get csr
}


function kube_approve_csr() { # Approve the pending csr
    echo '[*] Approve the pending csr'
    kubectl certificate approve $USER-k8s-access
}


function kube_retreive_signed_csr() { #  Retrieve the signed CSR and print to file
    echo '[*] Retreive the CA signed crt'
    sleep 2
    kubectl get csr $USER-k8s-access -o jsonpath='{.status.certificate}' | base64 --decode > $USER-k8s-access.crt
}


function print_the_csr() { #  Print the User's crt file
    echo "[*] Printing "$USER"-k8s-access.crt"
    cat $USER-k8s-access.crt
}


function retreive_users_signed_ca() { #  Pull the Users CA signed file
    echo '[*] Retreiving the signed CA crt'
    kubectl config view -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' --raw | base64 --decode - > $USER-k8s-ca.crt
}


function kube_create_users_config() { #  Create users kubeconfig file.
    echo '[*] Creating the users kubeconfig file'
    kubectl config set-cluster $(kubectl config view -o jsonpath='{.clusters[0].name}') --server=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}') --certificate-authority=$USER-k8s-ca.crt --kubeconfig=$USER-k8s-config --embed-certs
}


function print_users_kubeconfig() { #  Print the kubeconfig file
    echo '[*] Print the User kubeconfig file'
    cat $USER-k8s-config
}


function create_user_into_kubeconfig() { #  Fill in the users for the kubeconfig file
    echo '[*] Import user into kubeconfig file'
    kubectl config set-credentials $USER --client-certificate=$USER-k8s-access.crt --client-key=$USER-k8s.key --embed-certs --kubeconfig=$USER-k8s-config
}


function create_context_into_kubeconfig() { #  Fill in the context for the kubeconfig file
    echo '[*] Import context into the user kubeconfig file'
    kubectl config set-context $USER --cluster=$(kubectl config view -o jsonpath='{.clusters[0].name}') --namespace=$USER --user=$USER --kubeconfig=$USER-k8s-config
}


function kube_create_user_namespace() { #  Create the User's namespace
    echo '[*] Creating the User namespace'
    kubectl create ns $USER
}


function specify_context_for_user() { #  Specify the context for User to use with kubectl commands.
    echo '[*] Specifying the user context for kubectl'
    kubectl config use-context $USER --kubeconfig=$USER-k8s-config
}


function kube_test_users_kubeconfig() { #  Test User's kubeconfig file
    echo '[*] Test user kubeconfig file'
    kubectl version --kubeconfig=$USER-k8s-config
}


function kube_test_user_pods() { #  See the running pods for user
    echo '[*] Print the user pods for the user namespace'
    kubectl get pods --kubeconfig=$USER-k8s-config
}


function kube_create_user_admin_role_to_user_pods() { #  Create admin RoleBind for User to User namespace
    echo '[*] Create admin RoleBind for user namespace'
    kubectl create rolebinding $USER-admin --namespace=$USER --clusterrole=admin --user=$USER
}

function give_user_their_files() { #  Print to Admin they need to send files to user
    echo "[*] That's it! Send the following files to the user in a SECURED setting."
    echo "    - "$USER"-k8s-config"
    echo "[*] Have them place this file in ~/.kube/config and make sure kubectl is installed on their client."
}


function kube_delete_user_rolebinding() { #  Delete the RoleBind user-admin
    echo "[*] Deleting RoleBind "$USER"-admin"
    kubectl delete rolebinding $USER-admin
}


function kube_delete_approved_csr() { #  Delete the CA signed csr
    echo "[*] Deleting CA Signed csr for "$USER""
    kubectl delete csr $USER-k8s-access
}


function kube_delete_user_namespace() {
    echo "[*] Deleting Namespace for "$USER""
    kubectl delete namespaces $USER
}


function delete_user_conf_files() {
    echo "[*] Deleting files:"
    echo $(ls $USER-k8s*)
    rm -rf $(ls $USER-k8s*)
}

############################
# Functions to be executed #
############################

case "$1" in
    -u)
        _run_as_root
        check_user_input
        create_key_and_csr
        kube_apply_csr_yaml
        kube_get_csr
        kube_approve_csr
        kube_retreive_signed_csr
        kube_get_csr
        #print_the_csr
        retreive_users_signed_ca
        kube_create_users_config
        #print_users_kubeconfig
        create_user_into_kubeconfig
        create_context_into_kubeconfig
        kube_create_user_namespace
        specify_context_for_user
        kube_test_users_kubeconfig
        kube_test_user_pods #  This one should fail since we are Forbidden
        kube_create_user_admin_role_to_user_pods
        kube_test_user_pods #  This should now show no pods, we are in!
        give_user_their_files
        ;;
    -d)
        _run_as_root
        check_user_input
        kube_delete_user_rolebinding
        kube_delete_approved_csr
        kube_delete_user_namespace
        delete_user_conf_files
        ;;
    -h)
        _help_menu
        ;;
    *)
        _help_menu
        ;;
esac