classdef mne_rt_data_client < mne_rt_client
    %MNE_RT_DATA_CLIENT Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        m_clientID = -1;
    end
    
    methods
        
        % =================================================================
        %% mne_rt_data_client
        function obj = mne_rt_data_client(host, port, numOfRetries)
            if (nargin < 3)
                numOfRetries = 20; % set to -1 for infinite
            end
            obj = obj@mne_rt_client(host, port, numOfRetries);%Superclass call
            obj.getClientId();
        end % mne_rt_data_client
        
        
        % =================================================================
        %% readInfo
        function [dtd] = readInfo(obj)
            import java.net.Socket
            import java.io.*
            % get a buffered data input stream from the socket
            t_inStream   = obj.m_TcpSocket.getInputStream;
            t_dataInStream = DataInputStream(t_inStream);
            
            
            dtd = [];
            
            t_bReadMeasBlockEnd = false;
            
            while(~t_bReadMeasBlockEnd)
                % read data from the socket - wait a short time first
                bytes_available = t_dataInStream.available;
                if(bytes_available == 0)
                    t_bReadMeasBlockEnd = true;
                end
                
                
                info = zeros(1, bytes_available, 'uint8');
                for i = 1:bytes_available
                    info(i) = t_dataInStream.readByte;
                end

                dtd = [dtd info];
            end
        
        end
        

        % =================================================================
        %% read_tag
        function [tag] = read_tag(obj)
            
            import java.net.Socket
            import java.io.*
            
            me='MNE_RT_DATA_CLIENT:read_tag';
            
            tag = [];

            if ~isempty(obj.m_TcpSocket)
                % get a buffered data input stream from the socket
                t_inStream   = obj.m_TcpSocket.getInputStream;
                t_dataInStream = DataInputStream(t_inStream);

                % read data from the socket
                bytes_available = t_inStream.available;
                fprintf(1, 'Reading %d bytes\n', bytes_available);
                
                %
                % read the tag info
                %
                tagInfo = [];
                while true
                    bytes_available = t_inStream.available;
                    
                    if(bytes_available >= 16)
                        tagInfo = mne_rt_data_client.read_tag_info(t_dataInStream);
                        break;
                    end

                    % pause 100ms before retrying
                    pause(0.1);
                end

                %
                % read the tag data
                %
                while true
                    bytes_available = t_inStream.available;
                    
                    if(bytes_available >= tagInfo.size)
                        tag = mne_rt_data_client.read_tag_data(t_dataInStream, tagInfo);
                        break;
                    end

                    % pause 100ms before retrying
                    pause(0.1);
                end
            end
        end
        
        % =================================================================
        %% setClientAlias
        function [info] = setClientAlias(obj, alias)            
            import java.net.Socket
            import java.io.*

            global MNE_RT;
            if isempty(MNE_RT)
                MNE_RT = mne_rt_define_commands();
            end
            
            info = [];
            
            if ~isempty(obj.m_TcpSocket)
                % get a buffered data input stream from the socket
                t_outStream   = obj.m_TcpSocket.getOutputStream;
                t_dataOutStream = DataOutputStream(t_outStream);

                mne_rt_data_client.sendFiffCommand(t_dataOutStream, MNE_RT.MNE_RT_SET_CLIENT_ALIAS, alias)
            end
        end
        
        % =================================================================
        %% getClientId
        function [id] = getClientId(obj)
            if(obj.m_clientID == -1)
            
                import java.net.Socket
                import java.io.*

                global FIFF;
                if isempty(FIFF)
                    FIFF = fiff_define_constants();
                end
                global MNE_RT;
                if isempty(MNE_RT)
                    MNE_RT = mne_rt_define_commands();
                end

                if ~isempty(obj.m_TcpSocket)
                    % get a buffered data input stream from the socket
                    t_outStream   = obj.m_TcpSocket.getOutputStream;
                    t_dataOutStream = DataOutputStream(t_outStream);

                    mne_rt_data_client.sendFiffCommand(t_dataOutStream, MNE_RT.MNE_RT_GET_CLIENT_ID)

                    % ID is send as answer
                    tag = obj.read_tag();
                    if (tag.kind == FIFF.FIFF_MNE_RT_CLIENT_ID)
                        obj.m_clientID = tag.data;
                    end                
                end
            end
            id = obj.m_clientID;
        end
    end
    
    methods(Static)
        % =================================================================
        %% sendFiffCommand
        function sendFiffCommand(p_dOutputStream, p_Cmd, p_data)
            global FIFF;
            if isempty(FIFF)
                FIFF = fiff_define_constants();
            end
            
            if (nargin == 3)
                data = char(p_data);
            elseif(nargin == 2)
                data = [];
            else
                error('Wrong number of arguments.');
            end
            
            
            kind = FIFF.FIFF_MNE_RT_COMMAND;
            type = FIFF.FIFFT_VOID;
            size = 4+length(data);% first 4 bytes are the command code
            next = 0;
            
            p_dOutputStream.writeInt(kind);
            p_dOutputStream.writeInt(type);
            p_dOutputStream.writeInt(size);
            p_dOutputStream.writeInt(next);
            p_dOutputStream.writeInt(p_Cmd);% first 4 bytes are the command code
            if(~isempty(data))
                p_dOutputStream.writeBytes(data);
            end
            p_dOutputStream.flush;
        end
        
        % =================================================================
        %% read_tag_data
        function [tag] = read_tag_data(p_dInputStream, p_tagInfo, pos)
        %
        % [tag] = read_tag_data(p_dInputStream, pos)
        %
        % Read one tag from a fif stream.
        % if pos is not provided, reading starts from the current stream position
        %

        %
        %   Author : Christoph Dinh and Matti Hamalainen, MGH Martinos Center
        %   License : BSD 3-clause
        %
            global FIFF;
            if isempty(FIFF)
                FIFF = fiff_define_constants();
            end

            me='MNE:fiff_read_tag_stream';

            if nargin == 3
                d_Input_Stream.skipBytes(pos);
            elseif nargin ~= 2
                error(me,'Incorrect number of arguments');
            end

            tag = p_tagInfo;

            %
            %   The magic hexadecimal values
            %
            is_matrix           = 4294901760; % ffff0000
            matrix_coding_dense = 16384;      % 4000
            matrix_coding_CCS   = 16400;      % 4010
            matrix_coding_RCS   = 16416;      % 4020
            data_type           = 65535;      % ffff
            %
            if tag.size > 0
                matrix_coding = bitand(is_matrix,tag.type);
                if matrix_coding ~= 0
            %         matrix_coding = bitshift(matrix_coding,-16);
            %         %
            %         %   Matrices
            %         %
            %         if matrix_coding == matrix_coding_dense
            %             %
            %             % Find dimensions and return to the beginning of tag data
            %             %
            %             pos = ftell(fid);
            %             fseek(fid,tag.size-4,'cof');
            %             ndim = fread(fid,1,'int32');
            %             fseek(fid,-(ndim+1)*4,'cof');
            %             dims = fread(fid,ndim,'int32');
            %             %
            %             % Back to where the data start
            %             %
            %             fseek(fid,pos,'bof');
            %             
            %             matrix_type = bitand(data_type,tag.type);
            %             
            %             if ndim == 2
            %                 switch matrix_type
            %                     case FIFF.FIFFT_INT
            %                         idata = fread(fid,dims(1)*dims(2),'int32=>int32');
            %                         tag.data = reshape(idata,dims(1),dims(2))';
            %                     case FIFF.FIFFT_JULIAN
            %                         idata = fread(fid,dims(1)*dims(2),'int32=>int32');
            %                         tag.data = reshape(idata,dims(1),dims(2))';
            %                     case FIFF.FIFFT_FLOAT
            %                         fdata = fread(fid,dims(1)*dims(2),'single=>double');
            %                         tag.data = reshape(fdata,dims(1),dims(2))';
            %                     case FIFF.FIFFT_DOUBLE
            %                         ddata = fread(fid,dims(1)*dims(2),'double=>double');
            %                         tag.data = reshape(ddata,dims(1),dims(2))';
            %                     case FIFF.FIFFT_COMPLEX_FLOAT
            %                         fdata = fread(fid,2*dims(1)*dims(2),'single=>double');
            %                         nel = length(fdata);
            %                         fdata = complex(fdata(1:2:nel),fdata(2:2:nel));
            %                         %
            %                         %   Note: we need the non-conjugate transpose here
            %                         %
            %                         tag.data = transpose(reshape(fdata,dims(1),dims(2)));
            %                     case FIFF.FIFFT_COMPLEX_DOUBLE
            %                         ddata = fread(fid,2*dims(1)*dims(2),'double=>double');
            %                         nel = length(ddata);
            %                         ddata = complex(ddata(1:2:nel),ddata(2:2:nel));
            %                         %
            %                         %   Note: we need the non-conjugate transpose here
            %                         %
            %                         tag.data = transpose(reshape(ddata,dims(1),dims(2)));
            %                     otherwise
            %                         error(me,'Cannot handle a 2D matrix of type %d yet',matrix_type)
            %                 end
            %             elseif ndim == 3
            %                 switch matrix_type
            %                     case FIFF.FIFFT_INT
            %                         idata = fread(fid,dims(1)*dims(2)*dims(3),'int32=>int32');
            %                         tag.data = reshape(idata,dims(1),dims(2),dims(3));
            %                     case FIFF.FIFFT_JULIAN
            %                         idata = fread(fid,dims(1)*dims(2)*dims(3),'int32=>int32');
            %                         tag.data = reshape(idata,dims(1),dims(2),dims(3));
            %                     case FIFF.FIFFT_FLOAT
            %                         fdata = fread(fid,dims(1)*dims(2)*dims(3),'single=>double');
            %                         tag.data = reshape(fdata,dims(1),dims(2),dims(3));
            %                     case FIFF.FIFFT_DOUBLE
            %                         ddata = fread(fid,dims(1)*dims(2)*dims(3),'double=>double');
            %                         tag.data = reshape(ddata,dims(1),dims(2),dims(3));
            %                     case FIFF.FIFFT_COMPLEX_FLOAT
            %                         fdata = fread(fid,2*dims(1)*dims(2)*dims(3),'single=>double');
            %                         nel = length(fdata);
            %                         fdata = complex(fdata(1:2:nel),fdata(2:2:nel));
            %                         tag.data = reshape(fdata,dims(1),dims(2),dims(3));
            %                     case FIFF.FIFFT_COMPLEX_DOUBLE
            %                         ddata = fread(fid,2*dims(1)*dims(2)*dims(3),'double=>double');
            %                         nel = length(ddata);
            %                         ddata = complex(ddata(1:2:nel),ddata(2:2:nel));
            %                         tag.data = reshape(ddata,dims(1),dims(2),dims(3));
            %                     otherwise
            %                         error(me,'Cannot handle a 3D matrix of type %d yet',matrix_type)
            %                 end
            %                 %
            %                 %   Permute
            %                 %
            %                 tag.data = permute(tag.data,[ 3 2 1 ]);
            %             else
            %                 error(me, ...
            %                     'Only two and three dimensional matrices are supported at this time');
            %             end
            %         elseif (matrix_coding == matrix_coding_CCS || matrix_coding == matrix_coding_RCS)
            %             %
            %             % Find dimensions and return to the beginning of tag data
            %             %
            %             pos = ftell(fid);
            %             fseek(fid,tag.size-4,'cof');
            %             ndim = fread(fid,1,'int32');
            %             fseek(fid,-(ndim+2)*4,'cof');
            %             dims = fread(fid,ndim+1,'int32');
            %             if ndim ~= 2
            %                 error(me,'Only two-dimensional matrices are supported at this time');
            %             end
            %             %
            %             % Back to where the data start
            %             %
            %             fseek(fid,pos,'bof');
            %             nnz   = dims(1);
            %             nrow  = dims(2);
            %             ncol  = dims(3);
            %             sparse_data = zeros(nnz,3);
            %             sparse_data(:,3) = fread(fid,nnz,'single=>double');
            %             if (matrix_coding == matrix_coding_CCS)
            %                 %
            %                 %    CCS
            %                 %
            %                 sparse_data(:,1)  = fread(fid,nnz,'int32=>double') + 1;
            %                 ptrs  = fread(fid,ncol+1,'int32=>double') + 1;
            %                 p = 1;
            %                 for j = 1:ncol
            %                     while p < ptrs(j+1)
            %                         sparse_data(p,2) = j;
            %                         p = p + 1;
            %                     end
            %                 end
            %             else
            %                 %
            %                 %    RCS
            %                 %
            %                 sparse_data(:,2)  = fread(fid,nnz,'int32=>double') + 1;
            %                 ptrs  = fread(fid,nrow+1,'int32=>double') + 1;
            %                 p = 1;
            %                 for j = 1:nrow
            %                     while p < ptrs(j+1)
            %                         sparse_data(p,1) = j;
            %                         p = p + 1;
            %                     end
            %                 end
            %             end
            %             tag.data = spconvert(sparse_data);
            %             tag.data(nrow,ncol) = 0.0;
            %         else
            %             error(me,'Cannot handle other than dense or sparse matrices yet')
            %         end
                else
                    %
                    %   All other data types
                    %
                    switch tag.type
                        %
                        %   Simple types
                        %
                        case FIFF.FIFFT_BYTE
                            tag.data = zeros(1, tag.size);
                            for i = 1:tag.size
                                tag.data(i) = p_dInputStream.readUnsignedByte;%fread(fid,tag.size,'uint8=>uint8');
                            end
                        case FIFF.FIFFT_SHORT
                            tag.data = zeros(1, tag.size/2);
                            for i = 1:tag.size/2
                                tag.data(i) = p_dInputStream.readShort;%fread(fid,tag.size/2,'int16=>int16');
                            end
                        case FIFF.FIFFT_INT
                            tag.data = zeros(1, tag.size/4);
                            for i = 1:tag.size/4
                                tag.data(i) = p_dInputStream.readInt;%fread(fid,tag.size/4,'int32=>int32');
                            end
                        case FIFF.FIFFT_USHORT
                            tag.data = zeros(1, tag.size/2);
                            for i = 1:tag.size/2
                                tag.data(i) = p_dInputStream.readUnsignedShort;%fread(fid,tag.size/2,'uint16=>uint16');
                            end
                        case FIFF.FIFFT_UINT
                            tag.data = zeros(1, tag.size/4);
                            for i = 1:tag.size/4
                                tag.data(i) = p_dInputStream.readInt;%fread(fid,tag.size/4,'uint32=>uint32');
                            end
                        case FIFF.FIFFT_FLOAT
                            tag.data = zeros(1, tag.size/4);
                            for i = 1:tag.size/4
                                tag.data(i) = p_dInputStream.readFloat;%fread(fid,tag.size/4,'single=>double');
                            end
            %             case FIFF.FIFFT_DOUBLE
            %                 tag.data = fread(fid,tag.size/8,'double');
            %             case FIFF.FIFFT_STRING
            %                 tag.data = fread(fid,tag.size,'uint8=>char')';
            %             case FIFF.FIFFT_DAU_PACK16
            %                 tag.data = fread(fid,tag.size/2,'int16=>int16');
            %             case FIFF.FIFFT_COMPLEX_FLOAT
            %                 tag.data = fread(fid,tag.size/4,'single=>double');
            %                 nel = length(tag.data);
            %                 tag.data = complex(tag.data(1:2:nel),tag.data(2:2:nel));
            %             case FIFF.FIFFT_COMPLEX_DOUBLE
            %                 tag.data = fread(fid,tag.size/8,'double');
            %                 nel = length(tag.data);
            %                 tag.data = complex(tag.data(1:2:nel),tag.data(2:2:nel));
            %                 %
            %                 %   Structures
            %                 %
            %             case FIFF.FIFFT_ID_STRUCT
            %                 tag.data.version = fread(fid,1,'int32=>int32');
            %                 tag.data.machid  = fread(fid,2,'int32=>int32');
            %                 tag.data.secs    = fread(fid,1,'int32=>int32');
            %                 tag.data.usecs   = fread(fid,1,'int32=>int32');
            %             case FIFF.FIFFT_DIG_POINT_STRUCT
            %                 tag.data.kind    = fread(fid,1,'int32=>int32');
            %                 tag.data.ident   = fread(fid,1,'int32=>int32');
            %                 tag.data.r       = fread(fid,3,'single=>single');
            %                 tag.data.coord_frame = 0;
            %             case FIFF.FIFFT_COORD_TRANS_STRUCT
            %                 tag.data.from = fread(fid,1,'int32=>int32');
            %                 tag.data.to   = fread(fid,1,'int32=>int32');
            %                 rot  = fread(fid,9,'single=>double');
            %                 rot = reshape(rot,3,3)';
            %                 move = fread(fid,3,'single=>double');
            %                 tag.data.trans = [ rot move ; [ 0  0 0 1 ]];
            %                 %
            %                 % Skip over the inverse transformation
            %                 % It is easier to just use inverse of trans in Matlab
            %                 %
            %                 fseek(fid,12*4,'cof');
            %             case FIFF.FIFFT_CH_INFO_STRUCT
            %                 tag.data.scanno    = fread(fid,1,'int32=>int32');
            %                 tag.data.logno     = fread(fid,1,'int32=>int32');
            %                 tag.data.kind      = fread(fid,1,'int32=>int32');
            %                 tag.data.range     = fread(fid,1,'single=>double');
            %                 tag.data.cal       = fread(fid,1,'single=>double');
            %                 tag.data.coil_type = fread(fid,1,'int32=>int32');
            %                 %
            %                 %   Read the coil coordinate system definition
            %                 %
            %                 tag.data.loc        = fread(fid,12,'single=>double');
            %                 tag.data.coil_trans  = [];
            %                 tag.data.eeg_loc     = [];
            %                 tag.data.coord_frame = FIFF.FIFFV_COORD_UNKNOWN;
            %                 %
            %                 %   Convert loc into a more useful format
            %                 %
            %                 loc = tag.data.loc;
            %                 if tag.data.kind == FIFF.FIFFV_MEG_CH || tag.data.kind == FIFF.FIFFV_REF_MEG_CH
            %                     tag.data.coil_trans  = [ [ loc(4:6) loc(7:9) loc(10:12) loc(1:3) ] ; [ 0 0 0 1 ] ];
            %                     tag.data.coord_frame = FIFF.FIFFV_COORD_DEVICE;
            %                 elseif tag.data.kind == FIFF.FIFFV_EEG_CH
            %                     if norm(loc(4:6)) > 0
            %                         tag.data.eeg_loc     = [ loc(1:3) loc(4:6) ];
            %                     else
            %                         tag.data.eeg_loc = [ loc(1:3) ];
            %                     end
            %                     tag.data.coord_frame = FIFF.FIFFV_COORD_HEAD;
            %                 end
            %                 %
            %                 %   Unit and exponent
            %                 %
            %                 tag.data.unit     = fread(fid,1,'int32=>int32');
            %                 tag.data.unit_mul = fread(fid,1,'int32=>int32');
            %                 %
            %                 %   Handle the channel name
            %                 %
            %                 ch_name   = fread(fid,16,'uint8=>char')';
            %                 %
            %                 % Omit nulls
            %                 %
            %                 len = 16;
            %                 for k = 1:16
            %                     if ch_name(k) == 0
            %                         len = k-1;
            %                         break
            %                     end
            %                 end
            %                 tag.data.ch_name = ch_name(1:len);
            %             case FIFF.FIFFT_OLD_PACK
            %                 offset   = fread(fid,1,'single=>double');
            %                 scale    = fread(fid,1,'single=>double');
            %                 tag.data = fread(fid,(tag.size-8)/2,'int16=>short');
            %                 tag.data = scale*single(tag.data) + offset;
            %             case FIFF.FIFFT_DIR_ENTRY_STRUCT
            %                 tag.data = struct('kind',{},'type',{},'size',{},'pos',{});
            %                 for k = 1:tag.size/16-1
            %                     kind = fread(fid,1,'int32');
            %                     type = fread(fid,1,'uint32');
            %                     tagsize = fread(fid,1,'int32');
            %                     pos  = fread(fid,1,'int32');
            %                     tag.data(k).kind = kind;
            %                     tag.data(k).type = type;
            %                     tag.data(k).size = tagsize;
            %                     tag.data(k).pos  = pos;
            %                 end
            %                 
                        otherwise
                            error(me,'Unimplemented tag data type %d',tag.type);

                    end
                end
            end

            % if tag.next ~= FIFF.FIFFV_NEXT_SEQ
            %     fseek(fid,tag.next,'bof');
            % end

            return;
        end
            
        % =================================================================
        %% read_tag_info
        function [tag] = read_tag_info(p_dInputStream, pos)
        %
        % [tag] = read_tag_info(p_dInputStream, pos)
        %
        % Read one tag from a fif stream.
        % if pos is not provided, reading starts from the current stream position
        %

        %
        %   Author : Christoph Dinh and Matti Hamalainen, MGH Martinos Center
        %   License : BSD 3-clause
        %
            global FIFF;
            if isempty(FIFF)
                FIFF = fiff_define_constants();
            end

            me='MNE:read_tag_info';

            if nargin == 2
                d_Input_Stream.skipBytes(pos);
            elseif nargin ~= 1
                error(me,'Incorrect number of arguments');
            end

            tag.kind = p_dInputStream.readInt;
            tag.type = p_dInputStream.readInt;
            tag.size = p_dInputStream.readInt;
            tag.next = p_dInputStream.readInt;

            return;
        end                    
    end
end

