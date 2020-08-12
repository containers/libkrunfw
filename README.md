# libkrunfw

```libkrunfw``` is a library bundling a Linux kernel in a dynamic library in a way that can be easily consumed by [libkrun](https://github.com/libkrun/libkrun).

By having the kernel bundled in a dynamic library, ```libkrun``` can leave to the linker the work of mapping the sections into the process, and then directly inject those mappings into the guest without any kind of additional work nor processing.

## Building

### Requirements
* The toolchain your distribution needs to build a Linux kernel.
* Python 3
* ```pyelftools``` (package ```python3-pyelftools``` in Fedora and Ubuntu)

### Building and installing the library
```
make
sudo make install
```

## License

This library bundles a Linux kernel but does not execute any code from it, acting as a mere storage format. As a consequence, this library does not constitute a derivative work of the Linux kernel. Thus, the following licenses apply:

* **Linux kernel**: GPL-2.0-only

* **Files contained in the ```patches``` directory**: GPL-2.0-only

* **Library code, including automatically-generated code**: LGPL-2.1-only

Therefore, distributions of this library in binary form are required to be accompanied by the source code of the Linux kernel bundled in the binary along with the code of the library itself, but other programs linking against this library are not required to be licensed under the GPL-2.0-only nor the LGPL-2.1-only licenses.
