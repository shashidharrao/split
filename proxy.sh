#!/bin/bash -xe

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
MAC=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/ | head -n1 | tr -d '/')
VPCCIDR=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-ipv4-cidr-blocks | tr '\n' ',')
REGION=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')

# Set proxy settings
whitelists=(
    localhost
    127.0.0.1
    169.254.169.254
    $VPCCIDR
    10.100.0.0/16
    .internal
    .apple.com
    .execute-api.${REGION}.amazonaws.com
    .s3.${REGION}.amazonaws.com
    .${REGION}.eks.amazonaws.com
    .${REGION}.vpce.amazonaws.com
    amazonlinux.${REGION}.amazonaws.com
    api.sagemaker.${REGION}.amazonaws.com
    cloudformation.${REGION}.amazonaws.com
    cloudtrail.${REGION}.amazonaws.com
    codebuild-fips.${REGION}.amazonaws.com
    codebuild.${REGION}.amazonaws.com
    config.${REGION}.amazonaws.com
    dynamodb.${REGION}.amazonaws.com
    ec2.${REGION}.amazonaws.com
    ec2messages.${REGION}.amazonaws.com
    elasticloadbalancing.${REGION}.amazonaws.com
    events.${REGION}.amazonaws.com
    kinesis.${REGION}.amazonaws.com
    kms.${REGION}.amazonaws.com
    logs.${REGION}.amazonaws.com
    monitoring.${REGION}.amazonaws.com
    runtime.sagemaker.${REGION}.amazonaws.com
    secretsmanager.${REGION}.amazonaws.com
    servicecatalog.${REGION}.amazonaws.com
    sns.${REGION}.amazonaws.com
    ssm.${REGION}.amazonaws.com
    ssmmessages.${REGION}.amazonaws.com
    sts.${REGION}.amazonaws.com
)
HTTP_PROXY=http://proxy.config.pcp.local:3128
NO_PROXY=$(IFS=,; echo "${whitelists[*]}")

# Changes a value in a configuration file or adds it to the bottom if missing.
# KEY will be searched from the beginning of the line
# VALUE will be appended to KEY. Make sure to include any separator in KEY
function set_line() {
    KEY=$1
    VALUE=$2
    FILE=$3
    grep -q "^$KEY" $FILE && sed -i "s|^$KEY.*|$KEY$VALUE|g" $FILE || echo $KEY$VALUE >> $FILE
}

# Set the proxy for future processes
if [ -f /etc/environment ]; then
    set_line "HTTP_PROXY=" "$HTTP_PROXY" "/etc/environment"
    set_line "HTTPS_PROXY=" "$HTTP_PROXY" "/etc/environment"
    set_line "NO_PROXY=" "$NO_PROXY" "/etc/environment"
    set_line "http_proxy=" "$HTTP_PROXY" "/etc/environment"
    set_line "https_proxy=" "$HTTP_PROXY" "/etc/environment"
    set_line "no_proxy=" "$NO_PROXY" "/etc/environment"
fi
# Set the proxy for shell logins
cat << EOF | sed 's/^ *//' > /etc/profile.d/proxy.sh
    export HTTPS_PROXY=$HTTP_PROXY
    export HTTP_PROXY=$HTTP_PROXY
    export NO_PROXY=$NO_PROXY
    export http_proxy=$HTTP_PROXY
    export https_proxy=$HTTP_PROXY
    export no_proxy=$NO_PROXY
EOF

# Set the proxy for shell logins (ubuntu)
if [ -d /etc/apt/apt.conf.d ]; then
    grep -q "^source /etc/profile.d/proxy.sh" /etc/bash.bashrc || echo "source /etc/profile.d/proxy.sh" >> /etc/bash.bashrc
fi

# Configure yum
if [ -f /etc/yum.conf ]; then
    set_line "proxy=" "$HTTP_PROXY" "/etc/yum.conf"
fi

# Configure apt
if [ -d /etc/apt/apt.conf.d ]; then
    if [ ! -f /etc/apt/apt.conf.d/00proxy ]; then touch /etc/apt/apt.conf.d/00proxy; fi
    set_line "Acquire::http::Proxy " "\"$HTTP_PROXY/\";" "/etc/apt/apt.conf.d/00proxy"
    set_line "Acquire::https::Proxy " "\"$HTTP_PROXY/\";" "/etc/apt/apt.conf.d/00proxy"
fi

# Configure docker
if [ -x "$(command -v docker)" ]; then
    if [ -x "$(command -v systemctl)" ]; then
        mkdir -p /etc/systemd/system/docker.service.d
        echo -e "[Service]\nEnvironmentFile=/etc/environment" > /etc/systemd/system/docker.service.d/proxy.conf
        systemctl daemon-reload && systemctl restart docker
    else
        set_line "export HTTP_PROXY=" "$HTTP_PROXY" "/etc/sysconfig/docker"
        set_line "export HTTPS_PROXY=" "$HTTP_PROXY" "/etc/sysconfig/docker"
        set_line "export NO_PROXY=" "$NO_PROXY" "/etc/sysconfig/docker"
        service docker restart
    fi
fi

# Configure kubelet
if [ -x "$(command -v kubelet)" ]; then
    mkdir -p /etc/systemd/system/kubelet.service.d
    echo -e "[Service]\nEnvironmentFile=/etc/environment" > /etc/systemd/system/kubelet.service.d/proxy.conf
    systemctl daemon-reload
fi

# Set the proxy variables
set -a; source /etc/environment

