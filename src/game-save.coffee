_ = require 'lodash'

Section = require './section'
Pokemon = require './pokemon'
Item = require './item'
{PcStorage} = require './pc-boxes'
textEncoding = require './text-encoding'

module.exports = class GameSave
	constructor: (buffer) ->
		@saveIndex = -1

		@read buffer

		Object.defineProperties @,
			publicId:
				enumerable: no
				get: => @trainerId & 0xFFFF

			privateId:
				enumerable: no
				get: => (@trainerId & 0xFFFF0000) >> 16

	read: (buffer) ->
		sections = new Array 14
		for i in [0...14]
			sectionBuffer = buffer.slice i * Section.size, (i+1) * Section.size

			section = Section.split sectionBuffer
			sections[section.id] = section

			@saveIndex = section.saveIndex

		@readSections sections

	readSections: (sections) ->
		pcBuffer = new Buffer 33744

		for section in sections
			{id, data} = section

			switch id
				when 0
					@name = textEncoding.decode data.slice 0x00, 0x00 + 7
					@gender = if (data.readUInt8 0x08) is 0 then 'male' else 'female'
					@trainerId = data.readUInt32LE 0x0A

					@timePlayed =
						hours: data.readUInt16LE 0x0E
						minutes: data.readUInt8 0x0E+2
						seconds: data.readUInt8 0x0E+3
						frames: data.readUInt8 0x0E+4

					gameCode = data.readUInt32LE 0xAC

					switch gameCode
						when 0
							# ruby/sapphire
							@game = 'ruby-sapphire'
							@securityKey = 0x00 # 0 xor x = x

						when 1
							# firered / leafgreen
							@game = 'firered-leafgreen'
							@securityKey = data.readUInt32LE 0x0AF8

						else
							# emerald
							@game = 'emerald'
							@securityKey = gameCode

				when 1
					offsets = (require './section1-offsets')[@game]

					teamSize = data.readUInt32LE offsets.teamSize
					teamData = data.slice offsets.teamStart, offsets.teamStart + teamSize*100

					@team = for i in [0...teamSize]
						pkmnData = teamData.slice i*100, (i+1)*100

						new Pokemon pkmnData

					@money = (data.readUInt32LE offsets.money) ^ @securityKey

					readInventorySlot = (targetSlot, securityKey) =>
						securityKey ?= @securityKey
						slotOrder = ['pc', 'item', 'keyItem', 'ball', 'tmHm', 'berry']

						offset = offsets.inventoryStart
						for slot in slotOrder
							break if slot is targetSlot

							offset += offsets.inventorySizes[slot] * Item.itemEntryLength

						size = offsets.inventorySizes[targetSlot]

						Item.readList data, offset, size, securityKey

					@pcItems = readInventorySlot 'pc', 0
					@inventory =
						item: readInventorySlot 'item'
						keyItem: readInventorySlot 'keyItem'
						ball: readInventorySlot 'ball'
						tmHm: readInventorySlot 'tmHm'
						berry: readInventorySlot 'berry'

				when 4
					if @game is 'firered-leafgreen'
						# there is such a thing as a rival here
						@rivalName = textEncoding.decode data.slice 0x0BCC, 0x0BCC+8

				when 5,6,7,8,9,10,11,12
					data.copy pcBuffer, (id - 5) * 3968, 0, 3968

				when 13
					data.copy pcBuffer, (id - 5) * 3968, 0, 2000

					@pcPkmnStorage = new PcStorage pcBuffer