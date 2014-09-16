///////////////////////////////////////////////////////////////////////////////////
// 
//  Copyright (c) 2014 Nailson <nailsonnego@gmail.com>
// 
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
// 
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
// 
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
///////////////////////////////////////////////////////////////////////////////////

package otlib.sprites
{
    import flash.display.BitmapData;
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;
    import flash.utils.Endian;
    
    import nail.errors.NullArgumentError;
    import nail.logging.Log;
    import nail.utils.FileUtil;
    
    import ob.commands.ProgressBarID;
    
    import otlib.assets.Assets;
    import otlib.core.Version;
    import otlib.core.otlib_internal;
    import otlib.events.ProgressEvent;
    import otlib.resources.Resources;
    import otlib.utils.ChangeResult;
    
    use namespace otlib_internal;
    
    [Event(name="complete", type="flash.events.Event")]
    [Event(name="change", type="flash.events.Event")]
    [Event(name="progress", type="otlib.events.ProgressEvent")]
    [Event(name="error", type="flash.events.ErrorEvent")]
    
    public class SpriteStorage extends EventDispatcher
    {
        //--------------------------------------------------------------------------
        // PROPERTIES
        //--------------------------------------------------------------------------
        
        private var _file:File;
        private var _stream:FileStream;
        private var _signature:uint;
        private var _spritesCount:uint;
        private var _extended:Boolean;
        private var _transparency:Boolean;
        private var _version:Version;
        private var _sprites:Dictionary;
        private var _loaded:Boolean;
        private var _rect:Rectangle;
        private var _point:Point;
        private var _bitmap:BitmapData;
        private var _blankSprite:Sprite;
        private var _alertSprite:Sprite;
        private var _headSize:uint;
        private var _changed:Boolean;
        
        //--------------------------------------
        // Getters / Setters
        //--------------------------------------
        
        public function get signature():uint { return _signature; }
        public function get spritesCount():uint { return _spritesCount; }
        public function get loaded():Boolean { return _loaded; }
        public function get changed():Boolean { return _changed; }
        public function get version():Version { return _version; }
        public function get isFull():Boolean { return (!_extended && _spritesCount == 0xFFFF); }
        public function get transparency():Boolean { return _transparency; }
        public function get alertSprite():Sprite { return _alertSprite; }
        
        //--------------------------------------------------------------------------
        // CONSTRUCTOR
        //--------------------------------------------------------------------------
        
        public function SpriteStorage()
        {
            _rect = new Rectangle(0, 0, Sprite.DEFAULT_SIZE, Sprite.DEFAULT_SIZE);
            _bitmap = new BitmapData(_rect.width, _rect.height, true, 0xFFFF00FF);
            _point = new Point();
        }
        
        //--------------------------------------------------------------------------
        // METHODS
        //--------------------------------------------------------------------------
        
        //--------------------------------------
        // Public
        //--------------------------------------
        
        public function load(file:File, version:Version, extended:Boolean, transparency:Boolean):void
        {
            if (!file) {
                throw new NullArgumentError("file");
            }
            
            if (!version) {
                throw new NullArgumentError("version");
            }
            
            this.onLoad(file, version, extended, transparency, false);
        }
        
        public function createNew(version:Version, extended:Boolean, transparency:Boolean):Boolean
        {
            if (!version) {
                throw new NullArgumentError("version");
            }
            
            if (_loaded) {
                this.dispose();
            }
            
            _version = version;
            _signature = version.sprSignature;
            _spritesCount = 1;
            _headSize = (extended || version.value >= 960) ? HEAD_SIZE_U32 : HEAD_SIZE_U16;
            _transparency = transparency;
            _blankSprite = new Sprite(0, transparency);
            _alertSprite = createAlertSprite(transparency);
            _sprites = new Dictionary();
            _sprites[0] = _blankSprite;
            _sprites[1] = new Sprite(1, transparency);
            _changed = true;
            _loaded = true;
            return true;
        }
        
        public function addSprite(pixels:ByteArray):ChangeResult
        {
            if (!pixels) {
                throw new NullArgumentError("pixels");
            }
            
            var result:ChangeResult = internalAddSprite(pixels);
            if (result.done && hasEventListener(Event.CHANGE)) {
                dispatchEvent(new Event(Event.CHANGE));
            }
            
            _changed = true;
            return result;
        }
        
        public function addSprites(sprites:Vector.<ByteArray>):ChangeResult
        {
            if (!sprites) {
                throw new NullArgumentError("sprites");
            }
            
            var result:ChangeResult = internalAddSprites(sprites);
            if (result.done && hasEventListener(Event.CHANGE)) {
                dispatchEvent(new Event(Event.CHANGE));
            }
            
            _changed = true;
            return result;
        }
        
        public function replaceSprite(id:uint, pixels:ByteArray):ChangeResult
        {
            if (id == 0 || id > _spritesCount) {
                throw new ArgumentError(Resources.getString("indexOutOfRange"));
            }
            
            if (!pixels) {
                throw new NullArgumentError("pixels");
            }
            
            if (pixels.length != Sprite.SPRITE_DATA_SIZE) {
                throw new ArgumentError("Parameter pixels has an invalid length.");
            }
            
            var result:ChangeResult = internalReplaceSprite(id, pixels);
            if (result.done && hasEventListener(Event.CHANGE)) {
                dispatchEvent(new Event(Event.CHANGE));
            }
            
            _changed = true;
            return result;
        }
        
        public function replaceSprites(sprites:Vector.<SpriteData>):ChangeResult
        {
            if (!sprites) {
                throw new NullArgumentError("sprites");
            }
            
            var result:ChangeResult = internalReplaceSprites(sprites);
            if (result.done && hasEventListener(Event.CHANGE)) {
                dispatchEvent(new Event(Event.CHANGE));
            }
            
            _changed = true;
            return result;
        }
        
        public function removeSprite(id:uint):ChangeResult
        {
            if (id == 0 || id > _spritesCount) {
                throw new ArgumentError(Resources.getString("indexOutOfRange"));
            }
            
            var result:ChangeResult = internalRemoveSprite(id);
            if (result.done && hasEventListener(Event.CHANGE)) {
                dispatchEvent(new Event(Event.CHANGE));
            }
            
            _changed = true;
            return result;
        }
        
        public function removeSprites(sprites:Vector.<uint>):ChangeResult
        {
            if (!sprites) {
                throw new NullArgumentError("sprites");
            }
            
            var result:ChangeResult = internalRemoveSprites(sprites);
            if (result.done && hasEventListener(Event.CHANGE)) {
                dispatchEvent(new Event(Event.CHANGE));
            }
            
            _changed = true;
            return result;
        }
        
        public function getSprite(id:uint):Sprite
        {
            if (id == uint.MAX_VALUE) return _alertSprite;
            
            if (_loaded && id <= _spritesCount) {
                var sprite:Sprite;
                if (_sprites[id] !== undefined)
                    sprite = Sprite(_sprites[id]);
                else 
                    sprite = readSprite(id);
                
                if (!sprite) {
                    sprite = _blankSprite;
                }
                
                return sprite;
            }
            return null;
        }
        
        public function getPixels(id:uint):ByteArray
        {
            if (_loaded) {
                var sprite:Sprite = getSprite(id);
                if (sprite) {
                    var pixels:ByteArray;
                    try
                    {
                        pixels =  sprite.getPixels();
                    } catch (error:Error) {
                        Log.error(Resources.getString("failedToGetSprite", id), error.getStackTrace());
                        return _alertSprite.getPixels();
                    }
                    return pixels;
                }
            }
            return null;
        }
        
        public function copyPixels(index:int, bitmap:BitmapData, x:int, y:int):void
        {
            if (!_loaded || !bitmap) return;
            
            var pixels:ByteArray = getPixels(index);
            if (!pixels) return;
            
            _point.setTo(x, y);
            _bitmap.setPixels(_rect, pixels);
            bitmap.copyPixels(_bitmap, _rect, _point, null, null, true);
        }
        
        /**
         * @param backgroundColor A 32-bit ARGB color value.
         */
        public function getBitmap(id:uint, backgroundColor:uint = 0x00000000):BitmapData
        {
            if (!_loaded || id == 0) return null;
            
            var pixels:ByteArray = getPixels(id);
            if (pixels) {
                pixels.position = 0;
                
                _point.setTo(0, 0);
                _bitmap.setPixels(_rect, pixels);
                
                var bmp:BitmapData = new BitmapData(Sprite.DEFAULT_SIZE, Sprite.DEFAULT_SIZE, true, backgroundColor);
                bmp.copyPixels(_bitmap, _rect, _point, null, null, true);
                return bmp;
            }
            return null;
        }
        
        public function hasSpriteId(id:uint):Boolean
        {
            if (_loaded && id <= _spritesCount)
            {
                return true;
            }
            return false;
        }
        
        /**
         * Checks if a sprite id and a sprite pixels are equal.
         * 
         * @param id The id of the sprite to compare.
         * @param pixels Sprite pixels to compare.
         */
        public function compare(id:uint, pixels:ByteArray):Boolean
        {
            if (!pixels) {
                throw new NullArgumentError("pixels");
            }
            
            if (pixels.length != Sprite.SPRITE_DATA_SIZE) {
                throw new ArgumentError("Parameter pixels has an invalid length.");
            }
            
            if (hasSpriteId(id)) {
                pixels.position = 0;
                var bmp1:BitmapData = new BitmapData(Sprite.DEFAULT_SIZE, Sprite.DEFAULT_SIZE, true, 0xFFFF00FF);
                bmp1.setPixels(bmp1.rect, pixels);
                var otherPixels:ByteArray = this.getPixels(id);
                otherPixels.position = 0;
                var bmp2:BitmapData = new BitmapData(Sprite.DEFAULT_SIZE, Sprite.DEFAULT_SIZE, true, 0xFFFF00FF);
                bmp2.setPixels(bmp2.rect, otherPixels);
                return (bmp1.compare(bmp2) == 0);
            }
            return false;
        }
        
        //--------------------------------------
        // Private
        //--------------------------------------
        
        private function readSprite(index:uint):Sprite
        {
            try
            {
                _stream.position = ((index - 1) * 4) + _headSize;
                
                var spriteAddress:uint  = _stream.readUnsignedInt();
                if (spriteAddress == 0) return null;
                
                _stream.position = spriteAddress;
                _stream.readUnsignedByte(); // Skip red
                _stream.readUnsignedByte(); // Skip green
                _stream.readUnsignedByte(); // Skip blue
                
                var sprite:Sprite = new Sprite(index, _transparency);
                var pixelDataSize:uint = _stream.readUnsignedShort();
                
                if (pixelDataSize != 0) {
                    _stream.readBytes(sprite.compressedPixels, 0, pixelDataSize);
                }
                
                return sprite;
            } 
            catch(error:Error)
            {
                Log.error(Resources.getString("failedToGetSprite", index), error.getStackTrace());
                return _alertSprite;
            }
            return null;
        }
        
        public function compile(file:File, version:Version, extended:Boolean, transparency:Boolean):Boolean
        {
            if (!file) {
                throw new NullArgumentError("file");
            }
            
            if (!version) {
                throw new NullArgumentError("version");
            }
            
            if (!_loaded) return false;
            
            extended = (extended || version.value >= 960);
            var equal:Boolean = FileUtil.equals(_file, file);
            var stream:FileStream;
            
            // If is unmodified and the version is equal only save raw bytes.
            if (!_changed &&
                _version.equals(version) &&
                _extended == extended &&
                _transparency == transparency) {
                if (!equal) {
                    FileUtil.copyToAsync(_file, file);
                }
                dispatchEvent(new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.SPR, _spritesCount, _spritesCount));
                return true;
            }
            
            var tmpFile:File = FileUtil.getDirectory(file).resolvePath("tmp_" + file.name);
            var done:Boolean;
            var headSize:uint;
            var count:uint;
            
            try
            {
                stream = new FileStream();
                stream.open(tmpFile, FileMode.WRITE);
                stream.endian = Endian.LITTLE_ENDIAN;
                stream.writeUnsignedInt(version.sprSignature); // Write spr signature.
                
                // Write sprites count.
                if (extended || version.value >= 960) {
                    count = _spritesCount;
                    headSize = HEAD_SIZE_U32;
                    stream.writeUnsignedInt(count);
                } else {
                    count = _spritesCount >= 0xFFFF ? 0xFFFE : _spritesCount;
                    headSize = HEAD_SIZE_U16;
                    stream.writeShort(count);
                }
                
                var addressPosition:uint = stream.position;
                var offset:uint = (count * 4) + headSize;
                var dispatchProgess:Boolean = this.hasEventListener(ProgressEvent.PROGRESS);
                var progressEvent:ProgressEvent = new ProgressEvent(ProgressEvent.PROGRESS, ProgressBarID.SPR);
                progressEvent.total = count;
                
                for (var i:uint = 1; i <= count; i++) {
                    stream.position = addressPosition;
                    
                    var sprite:Sprite = getSprite(i);
                    
                    if(sprite.isEmpty) {
                        stream.writeUnsignedInt(0); // Write address
                    } else {
                        sprite.transparent = transparency;
                        sprite.compressedPixels.position = 0;
                        
                        stream.writeUnsignedInt(offset); // Write address
                        stream.position = offset;
                        stream.writeByte(0xFF);          // Write red
                        stream.writeByte(0x00);          // Write blue
                        stream.writeByte(0xFF);          // Write green
                        stream.writeShort(sprite.length);  // Write sprite data size
                        
                        if (sprite.length > 0) {
                            stream.writeBytes(sprite.compressedPixels, 0, sprite.length);
                        }
                        
                        offset = stream.position;
                    }
                    
                    addressPosition += 4;
                    
                    if (dispatchProgess && (i % 10) == 0) {
                        progressEvent.loaded = i;
                        dispatchEvent(progressEvent);
                    }
                }
                
                stream.close();
                done = true;
            } 
            catch(error:Error)
            {
                dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, error.getStackTrace(), error.errorID));
                done = false;
            }
            
            if (done) {
                // Closes the current spr file
                if (equal) {
                    _stream.close();
                }
                
                // Delete old file.
                if (file.exists) {
                    file.deleteFile();
                }
                
                // Rename the temporary file
                FileUtil.rename(tmpFile, FileUtil.getName(file));
                
                // Reload all if equal.
                if (equal) {
                    this.onLoad(file, version, extended, transparency, true);
                }
            } else if (tmpFile.exists) {
                tmpFile.deleteFile();
            }
            return done;
        }
        
        public function isEmptySprite(id:uint):Boolean
        {
            if (_loaded && id <= _spritesCount) {
                if (_sprites[id] !== undefined) {
                    var sprite:Sprite = Sprite(_sprites[id]);
                    if (sprite) return sprite.isEmpty;
                } else {
                    _stream.position = ((id - 1) * 4) + _headSize;
                    var spriteAddress:uint = _stream.readUnsignedInt();
                    if (spriteAddress == 0) return true;
                    
                    _stream.position = spriteAddress;
                    _stream.readUnsignedByte(); // Skip red
                    _stream.readUnsignedByte(); // Skip green
                    _stream.readUnsignedByte(); // Skip blue
                    return (_stream.readUnsignedShort() == 0);
                }
            }
            return true;
        }
        
        public function dispose():void
        {
            if (_stream) {
                _stream.close();
                _stream = null;
            }
            
            _loaded = false;
            _spritesCount = 0;
            _signature = 0;
        }
        
        //--------------------------------------
        // Internal
        //--------------------------------------
        
        otlib_internal function internalAddSprite(pixels:ByteArray, result:ChangeResult = null):ChangeResult
        {
            result = result ? result : new ChangeResult();
            
            if (pixels.length != Sprite.SPRITE_DATA_SIZE) {
                return result.update(null, false, "Parameter pixels has an invalid length.");
            }
            
            if (this.isFull) {
                return result.update(null, false, Resources.getString("spritesLimitReached"));
            }
            
            var id:uint = ++_spritesCount;
            var sprite:Sprite = new Sprite(id, _transparency);
            if (!sprite.setPixels(pixels)) {
                var message:String = Resources.getString(
                    "failedToAdd",
                    Resources.getString("sprite"),
                    id);
                return result.update(null, false, message);
            }
            
            // Add sprite to list.
            _sprites[id] = sprite;
            _spritesCount = id;
            
            // Returns the pixels buffer position.
            pixels.position = 0;
            
            var data:SpriteData = SpriteData.createSpriteData(id, sprite.getPixels());
            return result.update([data], true);
        }
        
        otlib_internal function internalAddSprites(sprites:Vector.<ByteArray>, result:ChangeResult = null):ChangeResult
        {
            result = result ? result : new ChangeResult();
            
            var addedList:Array = [];
            var length:uint = sprites.length;
            for (var i:uint = 0; i < length; i++) {
                var added:ChangeResult = internalAddSprite(sprites[i], CHANGE_RESULT_HELPER);
                if (!added.done) {
                    return result.update(addedList, false, added.message);
                }
                addedList[i] = added.list[0];
            }
            return result.update(addedList, true);
        }
        
        otlib_internal function internalReplaceSprite(id:uint, pixels:ByteArray, result:ChangeResult = null):ChangeResult
        {
            result = result ? result : new ChangeResult();
            
            if (id == 0)
                return result.update(null, true);
            
            var sprite:Sprite = new Sprite(id, _transparency);
            if (!sprite.setPixels(pixels)) {
                var message:String = Resources.getString(
                    "failedToReplace",
                    Resources.getString("sprite"),
                    id);
                return result.update(null, false, message);
            }
            
            // Get the removed sprite.
            var removed:Sprite = getSprite(id);
            
            // Add sprite to list.
            _sprites[id] = sprite;
            
            // Return the ByteArray position.
            pixels.position = 0;
            var data:SpriteData = SpriteData.createSpriteData(id, removed.getPixels());
            return result.update([data], true);
        }
        
        otlib_internal function internalReplaceSprites(sprites:Vector.<SpriteData>, result:ChangeResult = null):ChangeResult
        {
            result = result ? result : new ChangeResult();
            
            var replacedList:Array = [];
            var length:uint = sprites.length;
            
            for (var i:uint = 0; i < length; i++) {
                var id:uint = sprites[i].id;
                var pixels:ByteArray = sprites[i].pixels;
                var replaced:ChangeResult = internalReplaceSprite(id, pixels, CHANGE_RESULT_HELPER);
                if (!replaced.done) {
                    return result.update(replacedList, false, replaced.message);
                }
                
                if (replaced.list)
                    replacedList[i] = replaced.list[0];
            }
            return result.update(replacedList, true);
        }
        
        otlib_internal function internalRemoveSprite(id:uint, result:ChangeResult = null):ChangeResult
        {
            result = result ? result : new ChangeResult();
            
            // Get the removed sprite.
            var removed:Sprite = getSprite(id);
            
            if (id == _spritesCount && id != 1) {
                delete _sprites[id];
                _spritesCount--;
            } else {
                // Add a blank sprite at index.
                _sprites[id] = new Sprite(id, _transparency);
            }
            
            var data:SpriteData = SpriteData.createSpriteData(id, removed.getPixels());
            return result.update([data], true);
        }
        
        otlib_internal function internalRemoveSprites(sprites:Vector.<uint>, result:ChangeResult = null):ChangeResult
        {
            result = result ? result : new ChangeResult();
            
            var removedList:Array = [];
            var length:uint = sprites.length;
            
            // Removes last sprite first
            sprites.sort(Array.NUMERIC | Array.DESCENDING);
            
            for (var i:uint = 0; i < length; i++) {
                var id:uint = sprites[i];
                if (id != 0 && hasSpriteId(id)) {
                    var removed:ChangeResult = internalRemoveSprite(id, CHANGE_RESULT_HELPER);
                    if (!removed.done) {
                        return result.update(removedList, false, removed.message);
                    }
                    removedList[removedList.length] = removed.list[0];
                }
            }
            return result.update(removedList, true);
        }
        
        //--------------------------------------
        // Private
        //--------------------------------------
        
        private function onLoad(file:File,
                                version:Version,
                                extended:Boolean,
                                transparency:Boolean,
                                reloading:Boolean):void
        {
            if (_loaded) {
                this.dispose();
            }
            
            if (!file.exists) {
                Log.error(Resources.getString("fileNotFound", file.nativePath));
                return;
            }
            
            _file = file;
            _version = version;
            _extended = (extended || version.value >= 960);
            _transparency = transparency;
            _stream = new FileStream();
            _stream.open(file, FileMode.READ);
            _stream.endian = Endian.LITTLE_ENDIAN;
            _signature = _stream.readUnsignedInt();
            _spritesCount = _extended ? _stream.readUnsignedInt() : _stream.readUnsignedShort();
            _headSize = _extended ? HEAD_SIZE_U32 : HEAD_SIZE_U16;
            _blankSprite = new Sprite(0, transparency);
            _alertSprite = createAlertSprite(transparency);
            _sprites = new Dictionary();
            _sprites[0] = _blankSprite;
            _changed = false;
            _loaded = true;
            
            if (!reloading) {
                dispatchEvent(new Event(Event.COMPLETE));
            }
        }
        
        private function createAlertSprite(transparent:Boolean):Sprite
        {
            var bitmap:BitmapData = (new Assets.ALERT_IMAGE).bitmapData;
            var sprite:Sprite = new Sprite(uint.MAX_VALUE, transparent);
            sprite.setPixels( bitmap.getPixels(bitmap.rect) );
            return sprite;
        }
        
        //--------------------------------------------------------------------------
        // STATIC
        //--------------------------------------------------------------------------
        
        private static const HEAD_SIZE_U16:uint = 6;
        private static const HEAD_SIZE_U32:uint = 8;
        private static const CHANGE_RESULT_HELPER:ChangeResult = new ChangeResult();
    }
}
