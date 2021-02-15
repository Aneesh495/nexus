using build

**
** Build script for nexus pod: Distributed In-Memory Data Grid and Reactive State Fabric.
**
class Build : BuildPod
{
  new make()
  {
    podName    = "nexus"
    summary    = "Distributed In-Memory Data Grid and Reactive State Fabric"
    version    = Version("1.0.0")
    depends    = [
      "sys 1.0",
      "concurrent 1.0",
      "inet 1.0",
      "util 1.0",
      "web 1.0",
      "wisp 1.0"
    ]
    srcDirs    = [
      `fan/core/`,
      `fan/storage/`,
      `fan/cluster/`,
      `fan/consensus/`,
      `fan/data/`,
      `fan/tx/`,
      `fan/wire/`,
      `fan/client/`,
      `fan/cli/`,
      `fan/test/`
    ]
  }
}
