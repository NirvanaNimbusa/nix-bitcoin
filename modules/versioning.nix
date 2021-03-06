{ config, pkgs, lib, ... }:

with lib;
let
  version = config.nix-bitcoin.configVersion;

  # Sorted by increasing version numbers
  changes = [
    {
      version = "0.0.26";
      condition = config.services.joinmarket.enable;
      message = let
        inherit (config.services.joinmarket) dataDir;
      in ''
        JoinMarket 0.8.0 moves from wrapped segwit wallets to native segwit wallets.

        If you have an existing wrapped segwit wallet, you have to manually migrate
        your funds to a new native segwit wallet.

        To migrate, you first have to deploy the new JoinMarket version:
        1. Set `nix-bitcoin.configVersion = "0.0.26";` in your configuration.nix
        2. Deploy the new configuration

        Then run the following on your nix-bitcoin node:
        1. Move your wallet:
           mv ${dataDir}/wallets/wallet.jmdat ${dataDir}/wallets/old.jmdat
        2. Autogenerate a new p2wpkh wallet:
           systemctl restart joinmarket
        3. Transfer your funds manually by doing sweeps for each mixdepth:
           jm-sendpayment -m <mixdepth> -N 0 old.jmdat 0 <destaddr>

           Run this command for every available mixdepth (`-m 0`, `-m 1`, ...).
           IMPORTANT: Use a different <destaddr> for every run.

           Explanation of the options:
           -m <mixdepth>: spend from given mixdepth.
           -N 0: don't coinjoin on this spend
           old.jmdat: spend from old wallet
           0: set amount to zero to do a sweep, i.e. transfer all funds at given mixdepth
           <destaddr>: destination p2wpkh address from wallet.jmdat with mixdepth 0

        Privacy Notes:
        - This method transfers all funds to the same mixdepth 0.
          Because wallet inputs at the same mixdepth can be considered to be linked, this undoes
          the unlinking effects of previous coinjoins and resets all funds to mixdepth 0.
          This only applies in case that the inputs to the new wallet are used for further coinjoins.
          When inputs are instead kept separate in future transactions, the unlinking effects of
          different mixdepths are preserved.
        - A different <destaddr> should be used for every transaction.
        - You might want to time stagger the transactions.
        - Additionally, you can use coin-freezing to exclude specific inputs from the sweep.

        More information at
        https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/v0.8.0/docs/NATIVE-SEGWIT-UPGRADE.md
      '';
    }
  ];

  incompatibleChanges = optionals
    (version != null && versionOlder lastChange)
    (builtins.filter (change: versionOlder change && (change.condition or true)) changes);

  errorMsg = ''

    This version of nix-bitcoin contains the following changes
    that are incompatible with your config (version ${version}):

    ${concatMapStringsSep "\n" (change: ''
      - ${change.message}(This change was introduced in version ${change.version})
    '') incompatibleChanges}
    After addressing the above changes, set nix-bitcoin.configVersion = "${lastChange.version}";
    in your nix-bitcoin configuration.
  '';

  versionOlder = change: (builtins.compareVersions change.version version) > 0;
  lastChange = builtins.elemAt changes (builtins.length changes - 1);
in
{
  options = {
    nix-bitcoin.configVersion = mkOption {
      type = with types; nullOr str;
      default = null;
      description = ''
        Set this option to the nix-bitcoin release version that your config is
        compatible with.

        When upgrading to a backwards-incompatible release, nix-bitcoin will throw an
        error during evaluation and provide hints for migrating your config to the
        new release.
      '';
    };
  };

  config = {
    # Force evaluation. An actual option value is never assigned
    system.extraDependencies = optional (builtins.length incompatibleChanges > 0) (builtins.throw errorMsg);
  };
}
