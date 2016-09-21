Stat = require './stat'
fs = require 'graceful-fs'
_path = require 'path'
crypto = require 'crypto'
convert = require './util/path-converter'

module.exports =
class FileSystemNode
  constructor: ({@name, @path, @digest, @content, tree, stat}, @parent) ->
    @stats = new Stat(stat)
    @setTree(tree)

  get: (path) ->
    return this if @pathEquals(path)

    if @mayContain(path)
      match = null

      @tree.find (node) ->
        result = node.get(path)
        if result?
          match = result
          true

      match

  getRelative: (path) ->
    @get("#{@path}/#{path}")

  pathEquals: (path) ->
    path is @path or path is @localPath()

  mayContain: (path) ->
    @stats.isDirectory() and
      (path.startsWith("#{@path}/") or path.startsWith("#{@localPath()}/"))

  has: (path) ->
    @get(path)?

  localPath: ->
    return unless @path?
    convert.remoteToLocal(@path)

  update: (serializedNode) ->
    node = @get(serializedNode.path)
    node.constructor(serializedNode, node.parent)
    node

  remove: (path) ->
    node = @get(path)
    parent = node.parent

    if parent?
      i = parent.tree.indexOf(node)
      parent.tree.splice(i, 1)[0]

  add: (serializedNode) ->
    parentPath = _path.dirname(serializedNode.path)
    parent = @get(parentPath)

    if parent?
      node = new FileSystemNode(serializedNode, parent)
      parent.tree.push(node)
      node

  setTree: (tree) ->
    @tree =
      if tree?
        tree.map (entry) => new FileSystemNode(entry, this)
      else
        []

  setContent: (content) ->
    @content = content

  setDigest: (digest) ->
    @digest = digest

  read: ->
    @buffer().toString('utf8')

  buffer: ->
    new Buffer(@content or  "", 'base64')

  entries: ->
    @tree.map (node) ->
      node.name

  list: (extension) ->
    if extension?
      entries = @entries().filter (entry) -> entry.endsWith(".#{extension}")

    (entries or @entries()).map (entry) => "#{@path}/#{entry}"

  traverse: (callback) ->
    callback(this)
    @tree.forEach (node) -> node.traverse(callback)

  map: (callback, excluded) ->
    initialValue = [callback(this)]

    @tree.reduce (mapped, node) ->
      if excluded? and node.path.match(excluded)
        return mapped

      mapped.concat(node.map(callback, excluded))
    , initialValue

  findPathsToSync: ->
    pathsToSync = []

    syncPromises = @map (node) ->
      node.needsSync().then (shouldSync) ->
        pathsToSync.push(node.path) if shouldSync
    , /node_modules$|.git$|tmp$|vendor$|\.db$/

    Promise.all(syncPromises).then ->
      pathsToSync

  needsSync: ->
    new Promise (resolve) =>
      fs.stat @localPath(), (err, stats) =>
        if err? or not @digest?
          return resolve(true)

        if stats.isDirectory()
          return resolve(false)

        hash = crypto.createHash('md5')
        stream = fs.createReadStream(@localPath())

        stream.on 'data', (data) ->
          hash.update(data, 'utf8')

        stream.on 'end', =>
          stream.close()
          localDigest = hash.digest('hex')
          return resolve(@digest isnt localDigest)

  serialize: ->
    tree = @tree.map (node) -> node.serialize()
    stat = @stats.serialize()

    {@name, @path, @digest, @content, tree, stat}
