
PV_DOCKER_IMAGE_ENTRYPOINT_ARGS ?= ""
PV_DOCKER_IMAGE_ENVS ?= ""
DOCKER_IMAGE_TAG ??= "latest"
DOCKER_IMAGE_EXTRA_TAGS ??= ""
OCI_IMAGE_TAG = "${DOCKER_IMAGE_TAG}"

# ==============================================================================
# Python Functions
# ==============================================================================
do_umoci_config[depends] += "skopeo-native:do_populate_sysroot"

python do_umoci_config() {
    import shlex
    import subprocess
    import sys
    import os
    
    imgdeploydir = d.getVar("IMGDEPLOYDIR")
    os.chdir(imgdeploydir)

    # Get variables from the datastore.
    pn = d.getVar("PN")
    entrypoint_args = d.getVar("PV_DOCKER_IMAGE_ENTRYPOINT_ARGS")
    docker_envs = d.getVar("PV_DOCKER_IMAGE_ENVS")
    image_name_base = d.getVar("IMAGE_NAME")
    image_name_suffix = d.getVar("IMAGE_NAME_SUFFIX") or ""
    image_name = f"{image_name_base}{image_name_suffix}-oci"
    oci_image_tag = d.getVar("OCI_IMAGE_TAG")

    # Use shlex.split to safely parse the envs, preserving quotes.
    try:
        parsed_envs = shlex.split(docker_envs)
    except ValueError as e:
        bb.fatal(f"Could not parse PV_DOCKER_IMAGE_ENVS {e}")

    # Use shlex.split to safely parse the arguments, preserving quotes.
    try:
        parsed_args = shlex.split(entrypoint_args)
    except ValueError as e:
        bb.fatal(f"Could not parse PV_DOCKER_IMAGE_ENTRYPOINT_ARGS: {e}")

    # Build the umoci command as a list of arguments.
    umoci_command = ["umoci", "config", "--image", f"{pn}-{oci_image_tag}-oci:{oci_image_tag}"]
    
    # Prepend '--config.cmd' to each argument and add to the command list.
    for env in parsed_envs:
        umoci_command.append("--config.env")
        umoci_command.append(f'{env}')
 
    # Prepend '--config.env' to each argument and add to the command list.
    for arg in parsed_args:
        umoci_command.append("--config.cmd")
        umoci_command.append(f'{arg}')

    bb.note(f"Executing umoci command: {' '.join(umoci_command)}")
    
    # Run the command.
    try:
        if len(parsed_args) > 0 or len (parsed_envs) > 0:
            subprocess.run(umoci_command, check=True)
    except FileNotFoundError:
        bb.fatal("'umoci' command not found. Ensure it is in the PATH or has a build-time dependency.")
    except subprocess.CalledProcessError as e:
        bb.fatal(f"umoci command failed with exit code {e.returncode}.")

    # Get variables from the datastore
    docker_image_name = d.getVar("DOCKER_IMAGE_NAME")
    docker_image_tag = d.getVar("DOCKER_IMAGE_TAG")
    docker_image_extra_tags = d.getVar("DOCKER_IMAGE_EXTRA_TAGS")
    image_basename = d.getVar("IMAGE_BASENAME")
    
    # Build the skopeo command
    skopeo_cmd = [
        "skopeo", "copy",
        f"--additional-tag={docker_image_name}:{docker_image_tag}",
        f"oci:{pn}-{oci_image_tag}-oci:{oci_image_tag}",
        f"docker-archive:{image_basename}-{oci_image_tag}-docker.tar"
    ]

    # Collect all tags for symlink creation
    all_tags = [docker_image_tag]

    if docker_image_extra_tags and docker_image_extra_tags.strip():
        extra_tags_list = docker_image_extra_tags.split()
        for tag in extra_tags_list:
            skopeo_cmd.insert(3, f"--additional-tag={docker_image_name}:{tag}")
        all_tags.extend(extra_tags_list)

    # After running skopeo_cmd, create symlinks
    import os

    # Main symlink without version
    main_symlink = f"{image_basename}-docker.tar"
    target_file = f"{image_basename}-{oci_image_tag}-docker.tar"

    if os.path.exists(main_symlink) or os.path.islink(main_symlink):
        os.remove(main_symlink)
    os.symlink(target_file, main_symlink)

    # Symlinks for each tag
    for tag in all_tags:
        tag_symlink = f"{image_basename}-{tag}-docker.tar"
        if tag_symlink != target_file:  # Don't create symlink to itself
            if os.path.exists(tag_symlink) or os.path.islink(tag_symlink):
                os.remove(tag_symlink)
            os.symlink(target_file, tag_symlink)
    
    bb.note(f"Executing skopeo command: {' '.join(skopeo_cmd)}")
    
    # Execute the skopeo command
    try:
        subprocess.run(skopeo_cmd, check=True, cwd=imgdeploydir)
        bb.note("Successfully created Docker archive")
    except FileNotFoundError:
        bb.fatal("'skopeo' command not found. Ensure it is in the PATH or has a build-time dependency.")
    except subprocess.CalledProcessError as e:
        bb.fatal(f"skopeo command failed with exit code {e.returncode}")
}

addtask do_umoci_config after do_image_oci before do_image_complete

