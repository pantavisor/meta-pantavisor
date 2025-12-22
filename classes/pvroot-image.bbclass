#
# pvroot image class
#
inherit image

cmd_tidy() {
	rm -rf ${IMAGE_ROOTFS}/etc
	rm -rf ${IMAGE_ROOTFS}/var
}

PACKAGE_INSTALL = "pantavisor-pvroot"
IMAGE_INSTALL = ""
IMAGE_LINGUAS = ""
IMAGE_TYPES_MASKED += " pvbspit pvrexportit"
IMAGE_PREPROCESS_COMMAND += "cmd_tidy"

ROOTFS_BOOTSTRAP_INSTALL = ""
MACHINE_FEATURES = ""
DISTRO_FEATURES = ""
IMAGE_FEATURES = ""

# allow to assemble pvroot images by making special rootfs
# allow bundling multiple pvrexports to initial state

# Set some defaults, but these should be overriden by each recipe if required
IMGDEPLOYDIR ?= "${WORKDIR}/deploy-${PN}-image-complete"

do_rootfs[dirs] = "${IMGDEPLOYDIR} ${DEPLOY_DIR_IMAGE}"

PVROOT_CONTAINERS ??= ""
PVROOT_CONTAINERS_CORE ??= ""
PVROOT_IMAGE_BSP ??= ""
PVROOT_IMAGE ??= ""

PVS_VENDOR_NAME ??= "generic"

DEPENDS += " pvr-native squashfs-tools-native"

IMAGE_BUILDINFO_FILE = "pvroot.build"

UBOOT_ENV_SUFFIX ?= "scr"
IMAGE_BOOT_FILES += "boot.${UBOOT_ENV_SUFFIX}"
IMAGE_BOOT_FILES += "oemEnv.txt"

# disable all features that distros might inject globally
# through local.conf or distro.conf (like in case of agl)
IMAGE_FEATURES = ""

FAKEROOT_CMD = "pseudo"

PANTA_MULTICONFIG ?= ""
PANTA_DEPLOY_DIR_IMAGE ?= "${DEPLOY_DIR_IMAGE}"

python __anonymous () {
    pn = d.getVar("PN")

    mc = d.getVar("PANTA_MULTICONFIG")

    d.appendVarFlag('do_rootfs_pvroot', 'mcdepends' if mc != "" else 'depends', ' '+ ( "mc::"+mc+":pantavisor-bsp" if mc != "" else "pantavisor-bsp" ) +':do_compile')
    if d.getVar("PVROOT_IMAGE") == "yes":
        for img in d.getVar("PVROOT_IMAGE_BSP").split():
            d.appendVarFlag('do_rootfs_pvroot', 'mcdepends' if mc != "" else 'depends', ' '+ ( "mc::"+mc+":"+img if mc != "" else img ) +':do_image_complete')
    for img in d.getVar("PVROOT_CONTAINERS").split():
        d.appendVarFlag('do_rootfs_pvroot', 'mcdepends' if mc != "" else 'depends', ' '+ ( "mc::"+mc+":"+img if mc != "" else img ) +':do_deploy')
    for img in d.getVar("PVROOT_CONTAINERS_CORE").split():
        d.appendVarFlag('do_rootfs_pvroot', 'mcdepends' if mc != "" else 'depends', ' '+ ( "mc::"+mc+":"+img if mc != "" else img ) +':do_deploy')

    d.appendVarFlag('do_rootfs_pvroot', 'mcdepends' if mc != "" else 'depends', ' '+ ( "mc::"+mc+":virtual/bootloader"+img if mc != "" else "virtual/bootloader" ) +':do_deploy')
    d.delVarFlag("do_fetch", "noexec")
    d.delVarFlag("do_unpack", "noexec")
}

PSEUDO_IGNORE_PATHS .= ",${WORKDIR}/pvrrepo,${WORKDIR}/pvrconfig,${WORKDIR}/home,${WORKDIR}/tmp"

def _pvr_pvroot_images_deploy(d, factory, images, my_env):

    import tempfile
    import subprocess
    from pathlib import Path
    import shutil

    if True:
        tmpdir=d.getVar("WORKDIR") + "/pvrrepo"
        machine=d.getVar("MACHINE")
        configdir=d.getVar("WORKDIR") + "/pvrconfig"
        deployrootfs=d.getVar("IMAGE_ROOTFS") + "/trails/0"
        deployimg=d.getVar("PANTA_DEPLOY_DIR_IMAGE")
        Path(deployrootfs).mkdir(parents=True, exist_ok=True)
        Path(tmpdir).mkdir(parents=True, exist_ok=True)

        bspImage = d.getVar("PVROOT_IMAGE_BSP")
        versionsuffix = d.getVar("IMAGE_VERSION_SUFFIX")

        for img in images:
            if img == d.getVar("PVROOT_IMAGE_BSP") and not d.getVar("PVROOT_IMAGE") == "yes":
                continue

            if factory is True:
                shutil.copy2(deployimg + "/" + img + ".pvrexport.tgz", d.getVar("IMAGE_ROOTFS") + "/factory-pkgs.d/")
            else:
                imgpath = tmpdir + "/" + img + versionsuffix + ".pvrexport"
                Path(imgpath).mkdir(parents=True,exist_ok=True)
                process = subprocess.run(
                    ['tar', '--no-same-owner', '-xvf', deployimg + "/" + img + '.pvrexport.tgz' ],
                    cwd=Path(imgpath),
                    env=my_env
                )
                print ("completed tar process: %d" % process.returncode)

                process = subprocess.run(
                    ['pvr', 'deploy', deployrootfs,
                     imgpath ],
                    cwd=Path(tmpdir),
                    env=my_env
                )
                print ("completed pvr deploy process: %d" % process.returncode)

        # always mix-in pantavisor-bsp pvrexport
        pvrexportpath= deployimg + "/pantavisor-bsp-" + machine + '.pvrexport.tgz'
        imgpath = tmpdir + "/pantavisor-bsp-" + machine + versionsuffix + ".pvrexport"
        Path(imgpath).mkdir(parents=True,exist_ok=True)
        process = subprocess.run(
            ['tar', '--no-same-owner', '-xvf', pvrexportpath ],
             cwd=Path(imgpath),
             env=my_env
        )
        print ("completed tar process: %d" % process.returncode)

        process = subprocess.run(
                    ['pvr', 'deploy', deployrootfs,
                     imgpath ],
                    cwd=Path(tmpdir),
                    env=my_env
                )
        print ("completed pvr deploy process: %d" % process.returncode)


def do_rootfs_mixing(d, my_env):
    bspimage = d.getVar("PVROOT_IMAGE_BSP")
    if d.getVar("PVROOT_IMAGE") == "yes":
       _pvr_pvroot_images_deploy(d, False, bspimage.split(), my_env)
    images = d.getVar("PVROOT_CONTAINERS_CORE").split()
    _pvr_pvroot_images_deploy(d, False, images, my_env)
    images = d.getVar("PVROOT_CONTAINERS").split()
    _pvr_pvroot_images_deploy(d, True, images, my_env)

do_rootfs[dirs] += " ${WORKDIR}/tmp ${WORKDIR}/pvrrepo ${WORKDIR}/pvrconfig"
do_rootfs[cleandirs] += " ${WORKDIR}/tmp ${WORKDIR}/pvrrepo ${WORKDIR}/pvrconfig"

addtask rootfs_pvroot after do_rootfs before do_image

fakeroot python do_rootfs_pvroot(){
    from pathlib import Path
    from oe.utils import execute_pre_post_process
    import shutil
    import subprocess

    my_env = os.environ.copy()
    my_env["HOME"] = d.getVar("WORKDIR") + "/home"
    my_env["PVR_DISABLE_SELF_UPGRADE"] = "true"
    Path(d.getVar("WORKDIR") + "/tmp").mkdir(exist_ok=True)
    my_env["TMPDIR"] = d.getVar("WORKDIR") + "/tmp"
    my_env["FAKEROOT_CMD"] = d.getVar("FAKEROOT_CMD")

    traildir = d.getVar("IMAGE_ROOTFS") + "/trails/0/"

    testfile = d.getVar("IMAGE_ROOTFS") + "/test"

    devca = Path(d.getVar("WORKDIR") + "/pv-developer-ca_${PVS_VENDOR_NAME}/pvs/pvs.defaultkeys.tar.gz")
    Path(my_env["HOME"] + "/.pvr").mkdir(parents=True, exist_ok=True)
    if devca.is_file():
       process = subprocess.run(
            ['tar', '--no-same-owner', '-xf', devca.as_posix()],
            cwd=Path(my_env["HOME"] + "/.pvr"),
            env=my_env
       )
       print ("completed unpack of developer ca in %s of %s: %d" % (my_env["HOME"] + "/.pvr", devca.as_posix(), process.returncode))

    altkey = Path(d.getVar("WORKDIR") + "/pvs/key.default.pem")
    if altkey.is_file():
        my_env["PVR_SIG_KEY"] = altkey.as_posix()
    altx5c = Path(d.getVar("WORKDIR") + "/pvs/x5c.default.pem")
    if altx5c.is_file():
        my_env["PVR_X5C_PATH"] = altx5c.as_posix()
    altca = Path(d.getVar("WORKDIR") + "/pvs/ca-certificates.crt")
    if altca.is_file():
        my_env["PVR_SIG_CACERTS"] = altca.as_posix()

    process = subprocess.run(
         ['pvr', 'checkout', '-c'],
         cwd=Path(traildir),
         env=my_env
    )
    print ("completed pvr checkout -c for skel process: %d" % process.returncode)
    process = subprocess.run(
         ['pvr', 'sig', 'add', '--raw', '_pvskel',
          '--include', 'device-envelope.json',
          '--include', '#spec',
          '--exclude', '__pvrsigbug__' ],
         cwd=Path(traildir),
         env=my_env
    )
    print ("completed pvr sig add for skel process: %d" % process.returncode)
    process = subprocess.run(
         ['pvr', 'add'],
         cwd=Path(traildir),
         env=my_env
    )
    print ("completed pvr add for skel process: %d" % process.returncode)
    process = subprocess.run(
         ['pvr', 'commit'],
         cwd=Path(traildir),
         env=my_env
    )
    print ("completed pvr commit for skel process: %d" % process.returncode)

    do_rootfs_mixing(d, my_env)

    execute_pre_post_process(d, d.getVar('PVROOTFS_POSTPROCESS_COMMAND'))
}

PVROOTFS_POSTPROCESS_COMMAND += "${@'install_bootscr;' if d.getVar('DISTRO_UBOOT_DEFAULT_SCRIPT') else ''}"

install_bootscr() {
    install -d ${IMAGE_ROOTFS}/boot
    install -m 0644 ${DEPLOY_DIR_IMAGE}/boot.scr ${IMAGE_ROOTFS}/boot/
}

rootfs_pvroot[depends] += "${@'%s:do_deploy' % d.getVar('DISTRO_UBOOT_DEFAULT_SCRIPT') if d.getVar('DISTRO_UBOOT_DEFAULT_SCRIPT') else ''}"

