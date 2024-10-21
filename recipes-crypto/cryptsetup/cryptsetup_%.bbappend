# prevent udev as default dev manager being installed as dependency
PACKAGECONFIG:remove = "ssh-token udev blkid gcrypt gcrypt-pbkdf2 "
