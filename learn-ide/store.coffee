fs = require 'fs-plus'
_path = require 'path'
VirtualFile = require './virtual-file'
ShellAdapter = require './util/shell-adapter'
FSAdapter = require './util/fs-adapter'
PathConverter = require './util/path-converter'

serverURI = 'ws://vm02.students.learn.co:3304/background_sync'
token     = atom.config.get('integrated-learn-environment.oauthToken')

class LearnStore
  constructor: ->
    @virtualEntries = {}

    @projectPaths = atom.project.getPaths()
    @projectPaths.forEach (path) -> atom.project.removePath(path)

    @localRoot = _path.join(atom.configDirPath, '.learn-ide')
    @convert = new PathConverter(@localRoot)

    @fs = new FSAdapter(this)
    @shell = new ShellAdapter(this)

    @websocket = new WebSocket("#{serverURI}?token=#{token}")
    @handleEvents()

  handleEvents: ->
    messageCallbacks =
      sync: @onSync
      build: @onBuild
      fetch: @onFetch
      change: @onChange
      rescue: @onRescue

    @websocket.onopen = (event) =>
      @send {command: 'build'}

    @websocket.onmessage = (event) ->
      {type, payload} = JSON.parse(event.data)
      console.log 'RECEIVED:', type
      messageCallbacks[type]?(payload)

    @websocket.onerror = (err) ->
      console.error('error with the websocket')
      console.log(err)

  package: ->
    # todo: update package name
    atom.packages.getActivePackage('tree-view')

  treeView: ->
    @package()?.mainModule?.treeView

  send: (msg) ->
    convertedMsg = @convert.remoteMessage(msg)
    console.log 'SEND:', convertedMsg
    payload = JSON.stringify(convertedMsg)
    @websocket.send(payload)

  # ------------
  # initial sync
  # ------------

  fetch: (paths) ->
    pathsToFetch = paths.map (path) => @convert.localToRemote(path)
    @send {command: 'fetch', paths: pathsToFetch}

  # -------------------
  # onmessage callbacks
  # -------------------

  onBuild: ({entries, root}) =>
    @virtualRoot = @convert.remoteToLocal(root)
    @virtualEntries = @convert.remoteEntries(entries, VirtualFile)
    atom.project.addPath(@virtualRoot)
    # TODO: persist title change, maybe use custom-title package
    document.title = 'Learn IDE - ' + @virtualRoot.replace("#{@localRoot}/", '')
    @send {command: 'sync'}
    @treeView()?.updateRoots()

  onSync: ({entries, root}) ->
    #virtualEntries = convert.remoteEntries(entries, @localRoot)
    #sync = new Sync(virtualEntries, "#{@localRoot}/#{root}")
    #sync.execute()

  onChange: ({entries, path, parent}) =>
    console.log 'CHANGE:', path
    @virtualEntries = @convert.remoteEntries(entries)

    parent = @convert.remoteToLocal(parent)
    @treeView()?.entryForPath(parent).reload()

    path = @convert.remoteToLocal(path)
    @treeView()?.selectEntryForPath(path)

  onFetch: ({path, attributes, contents}) =>
    # TODO: include mode and shiz?
    localPath = @convert.remoteToLocal(path)
    dirname = _path.dirname(localPath)
    return unless localPath? and dirname?
    fs.makeTreeSync(dirname) unless fs.existsSync(dirname)
    decoded = new Buffer(contents, 'base64').toString('utf8')
    fs.writeFile(localPath, decoded)

  onRescue: ({message, backtrace}) ->
    console.log 'RESCUE:', message, backtrace

  # -------------
  # Introspection
  # -------------

  getNode: (path) ->
    @virtualEntries[path]

  hasPath: (path) ->
    @virtualEntries.hasOwnProperty(path)

  isDirectory: (path) ->
    @stat(path).isDirectory()

  isFile: (path) ->
    @stat(path).isFile()

  isSymbolicLink: (path) ->
    @stat(path).isSymbolicLink()

  list: (path, extension) ->
    @getNode(path).list(extension)

  lstat: (path) ->
    # TODO: lstat
    @stat(path)

  read: (path) ->
    @getNode(path)

  readdir: (path) ->
    @getNode(path).entries

  realpath: (path) ->
    # TODO: realpath
    path

  stat: (path) ->
    @getNode(path)

  # ----------
  # Operations
  # ----------

  cp: (source, destination) ->
    @send {command: 'cp', source, destination}

  mv: (source, destination) ->
    @send {command: 'mv', source, destination}

  mkdirp: (path) ->
    @send {command: 'mkdirp', path}

  touch: (path) ->
    @send {command: 'touch', path}

  trash: (path) ->
    @send {command: 'trash', path}

module.exports = new LearnStore
