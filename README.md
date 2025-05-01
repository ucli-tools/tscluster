<h1> Ubuntu 24.04 Tailscale Cluster Setup</h1>

<h2> Table of Contents </h2>

- [Introduction](#introduction)
- [Installation](#installation)
- [Contributing](#contributing)
- [License](#license)

## Introduction

This script allows to set up a Tailscale cluster for one control node and multiple managed nodes.

## Installation

- Run the script on all nodes
  - Select control or managed type accordingly

```bash
# Download the script
wget https://raw.githubusercontent.com/Mik-TF/tailscale_cluster/refs/heads/main/tailscale_cluster.sh

# Run the script
bash ./tscluster.sh
```

## Contributing

Contributions are welcome! Please feel free to submit pull requests.

## License

This project is licensed under the [Apache 2.0 License](./LICENSE).
