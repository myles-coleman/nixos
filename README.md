# nixos

## new devices

Locally auth to github and clone the repo
``` bash
nix-shell -p gh
gh auth login --hostname github.com --git-protocol https
gh auth setup-git
gh repo clone https://github.com/myles-coleman/nixos

git config --global user.email "mylescoleman05@gmail.com"
git config --global user.name "Myles Coleman
```

