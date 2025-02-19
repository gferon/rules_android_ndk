# Copyright 2022 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""A repository rule for integrating the Android NDK."""

load(":sha256sums.bzl", "ndk_sha256")

def _ndk_platform(ctx):
    if ctx.os.name == "linux":
        return "linux"
    elif ctx.os.name.startswith("mac os"):
        return "darwin"
    elif ctx.os.name.startswith("windows"):
        return "windows"
    else:
        fail("Unsupported platform for the Android NDK: {}", ctx.os.name)

def _android_ndk_repository_impl(ctx):
    """Download and extract the Android NDK files.

    Args:
        ctx: An implementation context.

    Returns:
        A final dict of configuration attributes and values.
    """

    ndk_version = ctx.attr.version
    ndk_platform = _ndk_platform(ctx)
    ndk_url = "{base_url}/android-ndk-{version}-{platform}.zip".format(
        base_url = ctx.attr.base_url,
        version = ndk_version,
        platform = ndk_platform,
    )

    filename = ndk_url.split("/")[-1]
    sha256 = ndk_sha256(filename, ctx)
    prefix = "android-ndk-{}".format(ndk_version)

    ctx.download_and_extract(url = ndk_url, sha256 = sha256, stripPrefix = prefix)

    if ctx.os.name == "linux":
        clang_directory = "toolchains/llvm/prebuilt/linux-x86_64"
    elif ctx.os.name == "mac os x":
        # Note: darwin-x86_64 does indeed contain fat binaries with arm64 slices, too.
        clang_directory = "toolchains/llvm/prebuilt/darwin-x86_64"
    elif ctx.os.name == "windows":
        clang_directory = "toolchains/llvm/prebuilt/windows-x86_64"
    else:
        fail("Unsupported operating system:", ctx.os.name)

    sysroot_directory = "%s/sysroot" % clang_directory

    api_level = ctx.attr.api_level or 31

    result = ctx.execute([clang_directory + "/bin/clang", "--print-resource-dir"])
    if result.return_code != 0:
        fail("Failed to execute clang: %s" % result.stderr)
    clang_resource_directory = result.stdout.strip().split(clang_directory)[1].strip("/")

    # Use a label relative to the workspace from which this repository rule came
    # to get the workspace name.
    repository_name = Label("//:BUILD").workspace_name

    ctx.template(
        "BUILD.bazel",
        ctx.attr._template_ndk_root,
        {
            "{clang_directory}": clang_directory,
        },
        executable = False,
    )

    ctx.template(
        "target_systems.bzl",
        ctx.attr._template_target_systems,
        {
        },
        executable = False,
    )

    # NOTE: NDK r23 & r24 for linux includes BUILD.bazel. Overwrite it here.
    ctx.template(
        "%s/BUILD.bazel" % clang_directory,
        ctx.attr._template_ndk_clang,
        {
            "{repository_name}": repository_name,
            "{api_level}": str(api_level),
            "{clang_resource_directory}": clang_resource_directory,
            "{sysroot_directory}": sysroot_directory,
        },
        executable = False,
    )

    ctx.template(
        "%s/BUILD.bazel" % sysroot_directory,
        ctx.attr._template_ndk_sysroot,
        {
            "{api_level}": str(api_level),
        },
        executable = False,
    )

android_ndk_repository = repository_rule(
    attrs = {
        "path": attr.string(),
        "api_level": attr.int(),
        "version": attr.string(default = "r25c"),
        "base_url": attr.string(default = "https://dl.google.com/android/repository"),
        "sha256s": attr.string_dict(),
        "_build": attr.label(default = ":BUILD", allow_single_file = True),
        "_template_ndk_root": attr.label(default = ":BUILD.ndk_root.tpl", allow_single_file = True),
        "_template_target_systems": attr.label(default = ":target_systems.bzl.tpl", allow_single_file = True),
        "_template_ndk_clang": attr.label(default = ":BUILD.ndk_clang.tpl", allow_single_file = True),
        "_template_ndk_sysroot": attr.label(default = ":BUILD.ndk_sysroot.tpl", allow_single_file = True),
    },
    local = True,
    implementation = _android_ndk_repository_impl,
)

def android_ndk_register_toolchains(name = "androidndk", **kwargs):
    android_ndk_repository(
        name = name,
        **kwargs
    )
    native.register_toolchains("@%s//:all" % name)
    native.bind(
        name = "android/crosstool",
        actual = "@%s//:toolchain" % name,
    )
