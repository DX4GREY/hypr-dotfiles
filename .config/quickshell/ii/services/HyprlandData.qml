pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    // Internals
    property bool clientsQueued: false
    property bool layersQueued: false
    property bool monitorsQueued: false
    property bool workspacesQueued: false
    property bool activeWorkspaceQueued: false

    function updateWindowList() {
        if (getClients.running) {
            clientsQueued = true;
        } else {
            getClients.running = true;
        }
    }

    function updateLayers() {
        if (getLayers.running) {
            layersQueued = true;
        } else {
            getLayers.running = true;
        }
    }

    function updateMonitors() {
        if (getMonitors.running) {
            monitorsQueued = true;
        } else {
            getMonitors.running = true;
        }
    }

    function updateWorkspaces() {
        if (getWorkspaces.running) {
            workspacesQueued = true;
        } else {
            getWorkspaces.running = true;
        }
        if (getActiveWorkspace.running) {
            activeWorkspaceQueued = true;
        } else {
            getActiveWorkspace.running = true;
        }
    }

    function updateAll() {
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        updateAll();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            // console.log("Hyprland raw event:", event.name);
            if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
            if (event.name === "activespecial") {
                const dataString = event.data ?? "";
                const commaIndex = dataString.indexOf(",");
                if (commaIndex !== -1) {
                    const wsName = dataString.substring(0, commaIndex);
                    const monName = dataString.substring(commaIndex + 1);
                    if (monName && root.monitors && root.monitors.length > 0) {
                        root.monitors = root.monitors.map(m => {
                            if (m.name === monName) {
                                return Object.assign({}, m, {
                                    specialWorkspace: {
                                        id: wsName ? -98 : 0,
                                        name: wsName
                                    }
                                });
                            }
                            return m;
                        });
                    }
                }
            }
            updateAll();
        }
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                try {
                    root.windowList = JSON.parse(clientsCollector.text);
                    let tempWinByAddress = {};
                    for (var i = 0; i < root.windowList.length; ++i) {
                        var win = root.windowList[i];
                        tempWinByAddress[win.address] = win;
                    }
                    root.windowByAddress = tempWinByAddress;
                    root.addresses = root.windowList.map(win => win.address);
                } catch (e) {}
                if (root.clientsQueued) {
                    root.clientsQueued = false;
                    getClients.running = true;
                }
            }
        }
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(monitorsCollector.text);
                } catch (e) {}
                if (root.monitorsQueued) {
                    root.monitorsQueued = false;
                    getMonitors.running = true;
                }
            }
        }
    }

    Process {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                try {
                    root.layers = JSON.parse(layersCollector.text);
                } catch (e) {}
                if (root.layersQueued) {
                    root.layersQueued = false;
                    getLayers.running = true;
                }
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                try {
                    var rawWorkspaces = JSON.parse(workspacesCollector.text);
                    // Filter out invalid workspace ids (e.g. lock-screen temp workspace 2147483647 - N)
                    root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                    let tempWorkspaceById = {};
                    for (var i = 0; i < root.workspaces.length; ++i) {
                        var ws = root.workspaces[i];
                        tempWorkspaceById[ws.id] = ws;
                    }
                    root.workspaceById = tempWorkspaceById;
                    root.workspaceIds = root.workspaces.map(ws => ws.id);
                } catch (e) {}
                if (root.workspacesQueued) {
                    root.workspacesQueued = false;
                    getWorkspaces.running = true;
                }
            }
        }
    }

    Process {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                try {
                    root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);
                } catch (e) {}
                if (root.activeWorkspaceQueued) {
                    root.activeWorkspaceQueued = false;
                    getActiveWorkspace.running = true;
                }
            }
        }
    }
}
