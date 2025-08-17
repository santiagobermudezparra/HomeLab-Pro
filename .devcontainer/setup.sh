#!/bin/bash
set -e

# --- 0. Detect System Architecture
echo "🔎 Detecting system architecture..."
ARCH=$(uname -m)
ARCH_SUFFIX=""

if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    echo "Architecture detected: ARM64"
    ARCH_SUFFIX="arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    echo "Architecture detected: AMD64"
    ARCH_SUFFIX="amd64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi
echo "--------------------------------------------------------"

# --- 1. Fix kubeconfig permissions
echo "🔧 Setting up kubeconfig permissions..."
mkdir -p ~/.kube
cp .devcontainer/kubeconfig ~/.kube/config
sudo chown vscode:vscode ~/.kube/config
chmod 600 ~/.kube/config
echo "--------------------------------------------------------"

# --- 2. Install Kubernetes Client Tools
echo "📦 Installing Kubernetes client tools..."

# Install kubectl
echo "Installing kubectl..."
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH_SUFFIX}/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -r .DS_Store 2>/dev/null || true
    rm kubectl
else
    echo "kubectl is already installed. Skipping."
fi


#  Install K9s
echo "Installing K9s..."
if ! command -v k9s &> /dev/null; then
    # Create a temporary directory for safe extraction and cleanup
    temp_dir=$(mktemp -d)
    echo "Using temporary directory: $temp_dir"

    # Download and extract the archive into the temporary directory
    curl -LO "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH_SUFFIX}.tar.gz"
    tar -xzf k9s_Linux_${ARCH_SUFFIX}.tar.gz -C "$temp_dir"
    
    # Move the executable from the temp directory to a bin path
    sudo mv "${temp_dir}/k9s" /usr/local/bin/
    
    # Clean up the downloaded tarball and the temporary directory
    rm k9s_Linux_${ARCH_SUFFIX}.tar.gz
    rm -r "$temp_dir"
else
    echo "K9s is already installed. Skipping."
fi

# Install flux CLI
echo "Installing flux..."
if ! command -v flux &> /dev/null; then
    curl -s https://fluxcd.io/install.sh | sudo bash
else
    echo "flux is already installed. Skipping."
fi

# Install helm
echo "Installing helm..."
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "helm is already installed. Skipping."
fi
echo "--------------------------------------------------------"

# --- 3. Install kubectx and kubens
echo "📦 Installing kubectx and kubens..."
if [ ! -d "/opt/kubectx" ]; then
    sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
else
    echo "kubectx directory already exists. Skipping clone."
fi
sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
echo "--------------------------------------------------------"

# --- 4. Set up completions
echo "🔧 Setting up completions..."
echo 'source <(kubectl completion zsh)' >> ~/.zshrc
echo 'source <(flux completion zsh)' >> ~/.zshrc
echo 'source <(helm completion zsh)' >> ~/.zshrc
echo "--------------------------------------------------------"

# --- 5. Test Connectivity
echo "🧪 Testing connectivity with the K3s cluster..."
echo "📋 Installed tools and versions:"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || echo 'Not found')"
echo "k9s: $(k9s version --short 2>/dev/null || echo 'Not found')"
echo "flux: $(flux version --client 2>/dev/null || echo 'Not found')"
echo "helm: $(helm version --short 2>/dev/null || echo 'Not found')"
echo "--------------------------------------------------------"

# --- 6. Finalizing
echo "✅ HomeLab setup complete!"
echo "🚀 Your DevPod is now configured to connect to your K3s cluster."
echo "✅ Your dotfiles are also loaded with all aliases and tools!"
echo "--------------------------------------------------------"

# Source shell configuration
echo "🔄 Loading shell configuration..."
if [ -f ~/.zshrc ]; then
    source ~/.zshrc
fi


# Start fresh shell to load everything
echo "🚀 Starting a fresh shell..."
exec zsh