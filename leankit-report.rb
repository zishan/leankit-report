require 'leankitkanban'
require 'nokogiri'
require 'pry-debugger'

::PRIORITIES = {
  0 => 'Low',
  1 => 'Normal',
  2 => 'High',
  3 => 'Critical'
}

# SET UP CREDENTIALS
LeanKitKanban::Config.email = 'your.login@email.com'
LeanKitKanban::Config.password = 'your.password'
LeanKitKanban::Config.account = 'YOURCOMPANY.LEANKIT.COM'
LeanKitKanban::Config.debug = false

# SET UP DESIRED BOARD
::LEANKIT_BOARD_ID = 123456789

# SET UP CARD TYPES TO BE CAPTURED
::CARD_TYPES = ['Epic', 'Defect']


def get_tasks(board)
  board['Lanes'].map { |lane| lane['Cards'] }.flatten
end

def get_lanes(board)
  Hash[board['Lanes'].map { |l| [l['Id'], l] }]
end

def get_headers(lanes)
  lanes.select { |_id, l| l['ParentLaneId'] == 0 }
end

def get_header_id(lanes, task)
  header_ids = get_headers(lanes).keys
  lane_id = task['LaneId']
  parent_lane_id = lanes[lane_id]['ParentLaneId']
  while !parent_lane_id.to_s.empty? && parent_lane_id != 0 && !header_ids.include?(parent_lane_id) do
    lane_id = parent_lane_id
    parent_lane_id = lanes[lane_id]['ParentLaneId']
  end
  lane_id
end

def task_details(lanes, task)
  external_id = task['ExternalCardID']
  type = task['TypeName']
  priority = PRIORITIES[task['Priority']]
  lane = lanes[get_header_id(lanes, task)]['Title']
  title = Nokogiri::HTML(task['Title']).text
  assigned = task['AssignedUserName']
  blocked = task['IsBlocked'] ? 'blocked' : 'not blocked'
  url = "http://#{LeanKitKanban::Config.account.downcase}/Boards/View/#{LEANKIT_BOARD_ID}/#{task['Id']}"

  [external_id, type, priority, lane, assigned, blocked, title, url]
end

# puts "Retrieving board #{LEANKIT_BOARD_ID}"
board = LeanKitKanban::Board.find(LEANKIT_BOARD_ID).flatten.first

output = []
lanes = get_lanes(board)
tasks = get_tasks(board)

tasks.each do |task|
  details = task_details(lanes, task)

  if CARD_TYPES.include? task['TypeName']
    output << details
    # puts "Output count is now #{output.count}"
  end

  totalcount = task['TaskBoardTotalSize']
  if !totalcount.nil? && totalcount > 1
    # puts "Task #{task['Id']} has subtasks..."
    # puts "Retrieving task board for #{task['Id']}"
    taskboard = LeanKitKanban::TaskBoard.find(LEANKIT_BOARD_ID, task['Id']).flatten.first
    boardlanes = get_lanes(taskboard)
    subtasks = get_tasks(taskboard)
    details = subtasks.select { |subtask| CARD_TYPES.include? subtask['TypeName'] }.map { |subtask| task_details(boardlanes, subtask) }
    output = output.concat(details)
    # puts "Output count is now #{output.count}"
  end
end

output.each do |details|
  puts "\"" + details.join("\",\"") + "\""
end
