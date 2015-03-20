# Description:
#   register cron jobs to schedule messages on the current channel
#
# Commands:
#   hubot add job "<crontab format>" <message> - Schedule a cron job to say something
#   hubot add event "<crontab format>" <event> <params_as_json> - Schedule a cron job to emit an event
#   hubot list jobs - List current cron jobs
#   hubot remove job <id> - remove job
#
# Author:
#   miyagawa

cronJob = require('cron').CronJob

JOBS = {}
_ = require('lodash')

createNewJob = (robot, pattern, user, payload, type = "message") ->
  id = Math.floor(Math.random() * 1000000) while !id? || JOBS[id]
  if type == "message" || type == "event"
    job = registerNewJob robot, id, pattern, user, payload, type
  else
    robot.send "Invalid job type #{type}"
  robot.brain.data.cronjob[id] = job.serialize()
  id

registerNewJob = (robot, id, pattern, user, payload, type = "message") ->
  JOBS[id] = new Job(id, pattern, user, payload, type)

  flow = user?.flow
  flow_name = _.result(_.findWhere(robot.adapter.flows, { 'id': flow }), 'name');
  robot.logger.info "Job #{type} #{id}: \"#{pattern}\" started on #{flow_name} #{JSON.stringify(payload)}"

  JOBS[id].start(robot)
  JOBS[id]

module.exports = (robot) ->
  robot.brain.on "loaded", =>
    # Postpone execution so that flow's have been loaded
    setTimeout(() =>
      robot.brain.data.cronjob or= {}
      for own id, job of robot.brain.data.cronjob
        continue if JOBS[id]
        registerNewJob(robot, id, job[0], job[1], job[2], job[3])
    , 5000)

  robot.respond /(?:new|add) event "(.*?)" (.+?)(\s(.*))?$/i, (msg) ->
    try
      data = event: msg.match[2].trim(), payload: msg.match[4]?.trim()
      user = msg.message.user
      id = createNewJob robot, msg.match[1], user, data, "event"

      flow = user?.flow
      flow_name = _.result(_.findWhere(robot.adapter.flows, { 'id': flow }), 'name');

      msg.send "Event job #{id} created to #{flow_name}"
    catch error
      msg.send "Error caught parsing crontab pattern: #{error}. See http://crontab.org/ for the syntax"

  robot.respond /(?:new|add) job "(.*?)" (.*?)$/i, (msg) ->
    try
      user = msg.message.user
      flow = user?.flow
      flow_name = _.result(_.findWhere(robot.adapter.flows, { 'id': flow }), 'name');

      id = createNewJob robot, msg.match[1], user, msg.match[2], "message"
      msg.send "Job #{id} created to #{flow_name}"
    catch error
      msg.send "Error caught parsing crontab pattern: #{error}. See http://crontab.org/ for the syntax"

  robot.respond /(?:list|ls) jobs?/i, (msg) ->
    for own id, job of robot.brain.data.cronjob
      flow_name = _.result(_.findWhere(robot.adapter.flows, { 'id': job[1].flow }), 'name');
      msg.send "Job #{id}: \"#{job[0]}\" on #{flow_name} \"#{JSON.stringify(job[2])}\""

  robot.respond /(?:rm|remove|del|delete) job (\d+)/i, (msg) ->
    id = parseInt(msg.match[1], 10)
    user = msg.message.user
    if JOBS[id]
      flow = JOBS[id].user?.flow
      flow_name = _.result(_.findWhere(robot.adapter.flows, { 'id': flow }), 'name');

      JOBS[id].stop()
      delete robot.brain.data.cronjob[id]
      msg.send "Job #{id} deleted from flow #{flow_name}"
    else
      msg.send "Job #{id} does not exist anywhere"

class Job
  constructor: (id, pattern, user, data, type) ->
    @id = id
    @pattern = pattern
    @user = user
    @data = data
    @type = type

  start: (robot) ->
    @cronjob = new cronJob(@pattern, =>
      if @type == "event"
        @sendEvent robot
      else
        @sendMessage robot
    )
    @cronjob.start()

  stop: ->
    @cronjob.stop()

  serialize: ->
    [@pattern, @user, @data, @type]

  sendMessage: (robot) ->
    robot.send @user, @data

  sendEvent: (robot) ->
    robot.emit @data.event, @data.payload
