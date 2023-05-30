This README file contains information on the contents of the meta-pantavisor layer.

Please see the corresponding sections below for details.

Dependencies
============

  URI: https://github.com/yoctoproject/poky
  branch: kirkstone

  URI: https://github.com/openembedded/meta-openembedded
  Layers: meta-oe, meta-python, *meta-networking*
  branch: kirkstone

Patches
=======

Please submit any patches against the meta-pantavisor layer to our github project:

     https://github.com/pantavisor/meta-pantavisor


I. Adding the meta-pantavisor layer to your build
=================================================

Run 'bitbake-layers add-layer meta-pantavisor'


II. Adding pantavisor to your image
===================================

To add pantavisor in appengine mode to your image you simply have to add
"pantavisor" package to your image.

To get this done quickly on Poky core-image derived images you can use

    CORE_IMAGE_EXTRA_INSTALL += "pantavisor"

in your local.conf. This would add pantavisor to any image produced.


III. Produce Pantavisor Containers (pvrexports)
================================================

To produce Pantavisor containers we offer magic and convenience
that makes it trivial for you to produce both a BSP as well as
user space container from your images.

## Prepare your env

To use any of the container export facilities of this layer
you will have to ensure that GOVERSION 1.20 or higher is used.

For older yocto releases that have golang < 1.20 that means adding to
distro or local config:

```
GOVERSION = "1.20%"
```

This can also be done automatically by sourcing the delegate style
pv-oe-init-env script:

```
source pv-oe-init-env path/to/your/init-env <your arguments>
```

Example for vanilla poky:

```
source pv-oe-init-env ../poky/oe-init-env mybuild/dir
```

## Preparing env for BSP exports

Before you can produce proper Pantavisor BSPs from your image receipt
you will have to add

```
KERNEL_CLASSES += "pvbsp"
```

to your distro or local.conf.

We do this for you if you use the pvbsp-oe-init-env script as follows:

```
source pvbsp-oe-init-env /path/to/delegate/oe-init-dev ....
```

This will add the pvbsp kernel class as well as force GOVERSION 1.20%
already mentioned further above for now. Later this might grow
so remember to rerun that pvbsp-oe-init-env everytime you pull a new
revision of meta-pantavisor.

## pvrexport image as container

Your image might have lots of goodness you would like to carry
over in bulk to Pantavisor world. This can be often achieved
quite nicely by converting your userspace into a fully
permissive container. 

To produce such pvrexport of your user space you would add the
`image-pvrexport` class to IMAGE_CLASSES.

You can do that either by in the actual image receipt or at
distro/local.conf level.

For the inside-receipt approach remember to define the IMAGE_CLASSES
variable _before_ the `inherit image` line as otherwise it wont
get picked up properly.

Then simply build your image as usual. The pvrexport can be found
in ${DEPLOY_IMAGE_DIR/$DISTRO} (e.g. tmp/deploy/images/poky).

## pvrexport image as bsp container

To extract a pantavisor-ready BSP from your OE image build you can
add the `bspimage-pvrexport` class to IMAGE_CLASSES.

You can do that either by in the actual image receipt or at
distro/local.conf level.

For the inside-receipt approach remember to define the IMAGE_CLASSES
variable _before_ the `inherit image` line as otherwise it wont
get picked up properly.

Then simply build your image as usual. The pvrexport can be found
in ${DEPLOY_IMAGE_DIR/$DISTRO} (e.g. tmp/deploy/images/poky).

Example:

```
IMAGE_CLASSES += "bspimage-pvrexport"

inherit image

```

To select a specific DTB to be the "default" to include in the BSP you would
specify the PV_INIITAL_DTB variable;

```
IMAGE_CLASSES += "bspimage-pvrexport"

inherit image

PV_INITIAL_DTB = "imx6ull-blah.dtb"
```

Whether you need this or not depends on how your bootloader will load or not
load the dtb. The above will make the initial dtb available at a standard
location that boot loader scripts can guess easily. But often DTBs might
get appended to kernel or the bootloader will load the right dtb
based on a choice of names.

If in doubt reach out through https://community.pantavisor.io

IV. Producing Pantavisor System image with bsp and containers added
=====================================================================

To produce a remixed rootfs and image in pantavisor format you can
use the pvroot-image.bbclass which injects itself in the do_rootfs
task to produce an image that instead of having the typical Linux FHS
structure, has a pantavisor compatible structure.

An example image receipt for this is included in this meta layer.

See: recipes-core/images/image-minimal.bb

pvroot-image allows you to add the BSP from an inline yocto build

To try simply edit that file to your liking and build it with:

```
bitbake image-minimal
```


V. Support
===========

If in doubt reach out through https://community.pantavisor.io


