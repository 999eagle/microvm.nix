{ self, nixpkgs }:

{
  runQemu = { system
            , vcpu ? 1
            , mem ? 512
            , nixos
            , append ? ""
            , user ? null
            , interfaces ? [ { id = "eth0"; type = "user"; } ]
            }:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      arch = builtins.head (builtins.split "-" system);
      kernel = pkgs.linuxPackages.kernel;
      customKernel = pkgs.linuxPackages_custom {
        inherit (kernel) version src;
        configfile = builtins.fetchurl {
          url = "https://mergeboard.com/files/blog/qemu-microvm/defconfig";
          sha256 = "0ml8v19ir3vmhd948n7c0k9gw8br4d70fd02bfxv9yzwl6r1gvd9";
        };
      };
      rootfs = nixos.config.system.build.toplevel;
      vmTools = pkgs.callPackage ../vmtools.nix { rootModules = []; };
      initrd = "${vmTools.initrd}/initrd"; #nixos.config.system.boot.loader.initrdFile;
      _initrd = pkgs.makeInitrd {
        contents = [ {
          symlink = "/init";
          object = pkgs.writeScript "microvm-run-stage1" ''
            #! ${pkgs.initrdUtils}/bin/ash -e

            exec ash
          '';
        } ];
      };
      qemuCommand = nixpkgs.lib.escapeShellArgs ([
        "${pkgs.qemu}/bin/qemu-system-${arch}"
        "-M" "microvm,x-option-roms=off,isa-serial=off,rtc=off"
        "-m" (builtins.toString mem)
        "-cpu" "host"
        "-smp" (builtins.toString vcpu)
        "-no-acpi" "-enable-kvm"
        "-nodefaults" "-no-user-config"
        "-nographic"
        "-device" "virtio-serial-device"
        "-chardev" "stdio,id=virtiocon0"
        "-device" "virtconsole,chardev=virtiocon0"
        "-device" "virtio-rng-device"
        "-kernel" "${customKernel.kernel}/bzImage"
        "-initrd" "${initrd}"
        "-fsdev" "local,id=root,path=${rootfs},security_model=passthrough,readonly=on"
        "-device" "virtio-9p-device,fsdev=root,mount_tag=/dev/root"
        "-fsdev" "local,id=store,path=/nix/store,security_model=passthrough,readonly=on"
        "-device" "virtio-9p-device,fsdev=store,mount_tag=store"
        "-append" "console=hvc0 acpi=off reboot=t panic=-1 quiet rootfstype=9p rootflags=trans=virtio ro init=/init command=${rootfs}/init ${append}"
        "-sandbox" "on"
      ] ++
      (if user != null then [ "-user" user ] else []) ++
      (builtins.concatMap ({ id }: [
        "-netdev" "${type},id=${id}"
        "-device" "virtio-net-device,netdev=${id}"
      ]) interfaces)
      );
    in
      pkgs.writeScriptBin "run-qemu" ''
        #! ${pkgs.runtimeShell} -e

        exec ${qemuCommand}
      '';
}
