# Upstream Notes: Patch 0023 — overlayfs EOPNOTSUPP fix

## Summary

`ovl_real_fileattr_get()` in `fs/overlayfs/inode.c` translates `ENOIOCTLCMD` to
`ENOTTY` but misses `EOPNOTSUPP`, which FUSE servers (virtiofs, davfs2, mergerfs)
return when they don't implement `FS_IOC_GETFLAGS`. This causes every overlayfs
copy-up over a virtiofs lower layer to fail with "Operation not supported".

The fix is one line: translate `EOPNOTSUPP` alongside `ENOIOCTLCMD` in
`ovl_real_fileattr_get()`.

## Steps to upstream

### 1. Subscribe to mailing lists

- **linux-unionfs@vger.kernel.org** — overlayfs subsystem
- **linux-fsdevel@vger.kernel.org** — general filesystem development

Subscribe at https://subspace.kernel.org/subscribing.html

### 2. Identify the maintainer

```bash
cd linux && scripts/get_maintainer.pl -f fs/overlayfs/inode.c
```

The overlayfs maintainer is **Miklos Szeredi** (`miklos@szeredi.hu`).

### 3. Prepare the patch on a clean tree

```bash
git clone --depth=1 --branch v6.14 \
  https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
cd linux
```

Edit `fs/overlayfs/inode.c`, in `ovl_real_fileattr_get()`:

```c
// before (line ~724)
if (err == -ENOIOCTLCMD)
    err = -ENOTTY;

// after
if (err == -ENOIOCTLCMD || err == -EOPNOTSUPP)
    err = -ENOTTY;
```

Then:

```bash
git add fs/overlayfs/inode.c
git commit -s   # -s adds Signed-off-by (required by kernel policy)
git format-patch -1
```

### 4. Send with git send-email

```bash
git send-email \
  --to miklos@szeredi.hu \
  --cc linux-unionfs@vger.kernel.org \
  --cc linux-fsdevel@vger.kernel.org \
  0001-ovl-translate-EOPNOTSUPP-to-ENOTTY-in-ovl_real_fileattr_get.patch
```

## Suggested commit message

```
ovl: translate EOPNOTSUPP to ENOTTY in ovl_real_fileattr_get

FUSE servers that do not implement FS_IOC_GETFLAGS return -EOPNOTSUPP
from their ioctl handler.  vfs_fileattr_get() propagates this error
unchanged, but ovl_real_fileattr_get() only translates -ENOIOCTLCMD
to -ENOTTY.  The callers in copy_up.c treat -ENOTTY as "no fileattr
support" and continue, while -EOPNOTSUPP falls through to pr_warn()
and an error return, failing every overlayfs copy-up when the lower
layer is a FUSE/virtiofs filesystem.

Translate -EOPNOTSUPP alongside -ENOIOCTLCMD so all callers benefit.

This affects virtiofs, davfs2, mergerfs, and any FUSE server that
does not handle the FS_IOC_GETFLAGS ioctl.

Fixes: 72db82115d2b ("ovl: copy up sync/noatime fileattr flags")
Signed-off-by: Your Name <your@email.com>
```

The `Fixes:` tag tells stable maintainers to backport to LTS kernels.
`72db82115d2b` is the v5.15 commit that introduced `ovl_copy_fileattr()`.

## Evidence this is safe

### Error code taxonomy

| Error | Value | Meaning | Source |
|---|---|---|---|
| `ENOIOCTLCMD` | 515 | No `fileattr_get` inode op | VFS layer |
| `ENOTTY` | 25 | No such ioctl | Already handled by overlayfs |
| `EOPNOTSUPP` | 95 | Unsupported operation | FUSE ioctl dispatch |

All three mean "this filesystem doesn't support fileattr." The first is
already translated. The third should be too.

### Call chain

```
ovl_copy_fileattr()                          # copy_up.c
  -> ovl_real_fileattr_get()                 # inode.c  <- fix here
    -> vfs_fileattr_get()                    # fs/ioctl.c
      -> inode->i_op->fileattr_get()         # fuse_fileattr_get()
        -> fuse_priv_ioctl(FS_IOC_GETFLAGS)  # fs/fuse/ioctl.c
          -> FUSE_IOCTL to server
            -> server returns EOPNOTSUPP
```

### Precedent

1. **v5.16 — `94fd19752b28`**: Added `ENOTTY`/`EINVAL` handling in copy_up.c
   after regression report from Christoph Fritz.

2. **Christian Kohlschutter's patch**: Added `ENOSYS` for FUSE filesystems
   (davfs2). Same class of bug, different error code.
   https://lore.kernel.org/lkml/4B9D76D5-C794-4A49-A76F-3D4C10385EE0@kohlschutter.com/

3. **Andrey Albershteyn's series**: Proposed making `vfs_fileattr_get/set`
   return `EOPNOTSUPP` and translating in overlayfs.
   https://www.mail-archive.com/linuxppc-dev@lists.ozlabs.org/msg241626.html

### Why inode.c not copy_up.c

`ovl_real_fileattr_get()` is the translation layer between VFS and overlayfs.
It already normalizes `ENOIOCTLCMD -> ENOTTY`. Adding `EOPNOTSUPP` here fixes
all callers in one place, avoids scattering error-code lists, and matches the
upstream direction.

### Reproducer

```bash
# virtiofs as overlayfs lower layer, ext4 as upper
mount -t overlay overlay \
  -o lowerdir=/virtiofs,upperdir=/ext4/upper,workdir=/ext4/work /merged
mkdir /merged/tmp/foo
# mkdir: cannot create directory '/merged/tmp/foo': Operation not supported
# dmesg: overlayfs: failed to retrieve lower fileattr (/tmp, err=-95)
```

## References

- Current upstream copy_up.c: https://github.com/torvalds/linux/blob/master/fs/overlayfs/copy_up.c
- Kohlschutter ENOSYS patch: https://lore.kernel.org/lkml/4B9D76D5-C794-4A49-A76F-3D4C10385EE0@kohlschutter.com/
- Albershteyn vfs_fileattr EOPNOTSUPP series: https://www.mail-archive.com/linuxppc-dev@lists.ozlabs.org/msg241626.html
- v5.16 partial fix: https://www.spinics.net/lists/kernel/msg4231495.html
