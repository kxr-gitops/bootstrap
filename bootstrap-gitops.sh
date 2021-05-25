#!/bin/bash

GITOPS_OVERLAY="stable-dex"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

err() {
    echo; echo;
    echo -e "\e[97m\e[101m[ERROR]\e[0m ${1}"; shift; echo;
    while [[ $# -gt 0 ]]; do echo "    $1"; shift; done
    echo; exit 1;
}

# Ensure oc binary is present
builtin type -P oc &> /dev/null \
    || err "oc not found"

# Ensure oc is authenticated
OC_USER=$(oc whoami 2> /dev/null) \
    || err "oc not authenticated"

# Get OpenShift server
OC_SERVER=$(oc whoami --show-server 2> /dev/null) \
    || err "unable to get openshift server info"

# Ensure that current user can create csv in openshift-operators
oc auth can-i create subscription -n openshift-operators &> /dev/null \
    || err "Current user (${OC_USER}) cannot create subscription in ns/openshift-operators"

# Ensure we don't already have the gitops operator installed
oc get subscription openshift-gitops-operator -n openshift-operators &> /dev/null \
    && err "openshift-gitops-operator already present in ns/openshift-operators"

echo; echo;
echo "This will install the latest Red Hat OpenShift GitOps Operator on ${OC_SERVER}"
echo
echo -n "Press [Enter] to continue or [Ctrl-C] to abort "
read x
echo; echo;

echo
echo -n "Creating operator subscription ... "
oc create -k ${SCRIPT_DIR}/openshift-gitops-operator/overlays/${GITOPS_OVERLAY} &> /dev/null \
    && echo "ok" || { echo "failed" && exit 1; }

echo
echo -n "Waiting for CSV ... "
while test -z ${CSV}; do
    CSV=$(oc get subscription openshift-gitops-operator -n openshift-operators -o jsonpath="{.status.currentCSV}" 2> /dev/null)
    sleep 2
done
echo ${CSV}

echo
echo -n "Waiting for CSV to succeed ... "
while [ $(oc get csv ${CSV} -n openshift-operators -o jsonpath="{.status.phase}" 2> /dev/null) != "Succeeded" ]; do sleep 2; done \
    && echo ok

echo
echo -n "Waiting for argocd/openshift-gitops in ns/openshift-gitops ... "
while ! oc get argocd/openshift-gitops -n openshift-gitops &> /dev/null; do sleep 2; done \
    && echo "ok"

echo
echo -n "Patching argocd/openshift-gitops to use OpenShift authentication ..."
sleep 2
oc patch argocd openshift-gitops -n openshift-gitops --type=merge -p='{"spec":{"dex":{"openShiftOAuth":true}}}' &> /dev/null \
    && echo "ok" || { echo "failed" && exit 1; }

