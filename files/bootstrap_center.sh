# This script is executed on the center server

# install tiup
curl --proto '=https' --tlsv1.2 -sSf https://tiup-mirrors.pingcap.com/install.sh | sh

# install haproxy
sudo apt install -y haproxy mysql-client
sudo cp ~/haproxy.cfg /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy

# prepare go-tpc
GO_VERSION="1.25.12"
GO_ARCHIVE="go${GO_VERSION}.linux-amd64.tar.gz"
curl -fsSLO "https://go.dev/dl/${GO_ARCHIVE}"
echo "234828b7a89e0e303d2556310ee549fbcf253d28de937bac3da13d6294262ac1  ${GO_ARCHIVE}" | sha256sum --check
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "${GO_ARCHIVE}"
rm "${GO_ARCHIVE}"
sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
go version

git clone https://github.com/pingcap/go-tpc
cd go-tpc
make build
cd ..
