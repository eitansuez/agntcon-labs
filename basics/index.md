# Simple lab

Hello dear student.

In this lab you will learn some basic linux commands, such as `ls`, `pwd`, `cd`, and `mkdir`.

## The working directory

On Linux is a file system consisting primarily of files and directories (aka folders).

The command `pwd` will "print" to "standard output" your "current working directory."

Try it:

```shell
pwd
```

## Listing directories

With the `ls` command we can list the contents of the working directory:

```shell
ls
```

## Creating directories

Directories can be nested, meaning that they can exist inside each other.

In the current directory, create a "subdirectory" with the `mkdir` command:

```shell
mkdir my-folder
```

Run `ls` again and verify that `my-folder` is now in the listing:

```shell
ls
```

## Navigating directories

The `cd` command stands for "change directory" and it serve to change the current working directory.

```shell
cd my-folder
```

Run `pwd`:

```shell
pwd
```

The output should confirm that your current working directory has changed to `my-folder`.

Note that a file or a directory has what is called a "fully qualified path", text formatted in a way to show the full hierarchy of a file or directory:  the "path" from trunk to branch to leaf, so to speak.

## Summary

In this lab, we covered the basics of navigating the file system:

- `pwd` for discovering the current working directory
- `ls` for listing the contents of the current working directory
- `mkdir` to create subdirectories
- `cd` for changing the current working directory, or otherwise navigating to a different "spot" in the filesystem.

Congratulations on completing this lab.

