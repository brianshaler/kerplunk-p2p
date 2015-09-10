###
# Friend schema
###

module.exports = (mongoose) ->
  Schema = mongoose.Schema
  ObjectId = Schema.ObjectId

  FriendSchema = new Schema
    domain:
      required: true
      type: String
      index:
        unique: true
    name:
      type: String
    publicKey:
      required: true
      type: String
    following:
      required: true
      type: Boolean
      default: false
    requested:
      type: Boolean
      default: false
    requestedAt:
      type: Date
      default: Date.now
    ignored:
      type: Boolean
      default: false
    ignoredAt:
      type: Date
      default: Date.now
    updatedAt:
      type: Date
      default: Date.now
    createdAt:
      type: Date
      default: Date.now

  mongoose.model 'Friend', FriendSchema
