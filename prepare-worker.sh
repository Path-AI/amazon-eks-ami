#
# Custom steps for AMI building, meant to be run as a Packer Shell Processor.
#
# Args:
#
#   INSTANCE_TYPE: The instance type (example: 'p2.xlarge').

################################################################################
### Variables###################################################################
################################################################################

# OS distribution.
DISTRIBUTION=$(. /etc/os-release; echo $ID$VERSION_ID)
# Version of the NVIDIA driver to use.
NVIDIA_DRIVER_VERSION="390.77"
# Template directory.
TEMPLATE_DIR=${TEMPLATE_DIR:-/tmp/worker}
# URL to the NVIDIA Docker Runtime repository file.
NVIDIA_DOCKER_RUNTIME_REPO_URL="https://nvidia.github.io/nvidia-docker/${DISTRIBUTION}/nvidia-docker.repo"
# URL to the NVIDIA Driver installer.
NVIDIA_DRIVER_URL="http://us.download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"

################################################################################
### SSH Keys ###################################################################
################################################################################

cat $TEMPLATE_DIR/id_rsa.pub >> $HOME/.ssh/authorized_keys

################################################################################
### EFS ########################################################################
################################################################################

sudo yum install --assumeyes \
  https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm \
  amazon-efs-utils

################################################################################
### Flexvolume #################################################################
################################################################################

sudo yum install --assumeyes \
  gcc \
  python3 \
  python3-devel

sudo pip3 install \
  boto3 \
  botocore \
  psutil \
  requests

sudo mkdir --parents \
  /usr/libexec/kubernetes/kubelet-plugins/volume/exec/mle.pathai.com~flexvolume
sudo mv "${TEMPLATE_DIR}/flexvolume" \
  /usr/libexec/kubernetes/kubelet-plugins/volume/exec/mle.pathai.com~flexvolume/flexvolume

################################################################################
### NVIDIA #####################################################################
################################################################################

# Skip NVIDIA install if not on a p2.xlarge.
if [[ "$INSTANCE_TYPE" != "p2.xlarge" ]]
then
  echo "Not on a GPU image, skipping NVIDIA install."
else
  # Install kernel sources and corresponding development tools.
  sudo yum install --assumeyes kernel-devel

  # Download and install the NVIDIA driver.
  curl $NVIDIA_DRIVER_URL > "NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
  sudo sh "NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run" \
    --silent \
    --kernel-source-path $(ls -d  /usr/src/kernels/*)

  # Install the NVIDIA Docker runtime.
  curl --silent --location $NVIDIA_DOCKER_RUNTIME_REPO_URL | \
    sudo tee /etc/yum.repos.d/nvidia-docker.repo
  sudo yum install --assumeyes nvidia-docker2

  # Set the default runtime for Docker.
  sudo sed --in-place 's/"runtimes"/"default-runtime": "nvidia", "runtimes"/' \
    /etc/docker/daemon.json

  # Enable device plugins in Kubelet.
  #
  # NOTE: These seem to be enabled by default, this is for future reference.
  # sudo sed --in-place \
  #   's/--feature-gates=/--feature-gates=DevicePlugins=true,/' \
  #   /etc/systemd/system/kubelet.service

  # Clean-up.
  rm "NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
fi

################################################################################
### Clean-up ###################################################################
################################################################################

# Clean up Yum caches.
sudo yum clean all
