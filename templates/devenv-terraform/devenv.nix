{ pkgs, ... }:

{
  languages.terraform = {
    enable = true;
    lsp.enable = true;
  };

  packages = with pkgs; [
    just
    tflint
    terraform-docs
  ];

  enterShell = ''
    echo "Terraform development shell"
    terraform version
  '';
}
