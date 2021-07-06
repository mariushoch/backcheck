FROM docker.io/rockylinux/rockylinux:8

# bats is not yet in EPEL 8 (https://bugzilla.redhat.com/show_bug.cgi?id=1755945)
RUN curl -L "https://github.com/bats-core/bats-core/archive/refs/tags/v1.3.0.tar.gz" > /tmp/bats.tar.gz
RUN tar -xvzf /tmp/bats.tar.gz && bash bats-core*/install.sh /usr/local && rm /tmp/bats.tar.gz && rm -rf bats-core*
RUN dnf --setopt=install_weak_deps=False install -y 'dnf-command(config-manager)'
RUN dnf -y config-manager --set-enabled powertools
RUN dnf --nodocs --setopt=install_weak_deps=False -y install rsync bubblewrap sudo
RUN dnf clean all -y
