FROM docker.io/rockylinux/rockylinux:8

RUN dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
RUN dnf --setopt=install_weak_deps=False install -y 'dnf-command(config-manager)'
RUN dnf -y config-manager --set-enabled powertools
RUN dnf --nodocs --setopt=install_weak_deps=False -y install rsync bubblewrap sudo bats
RUN dnf clean all -y
