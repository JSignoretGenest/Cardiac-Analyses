classdef ECG_Process < handle
    %% ECG_Process - GUI to process ECG to extract heart rate.
    % Consists in three main steps:
    %   - ECG preprocessing: substraction of a smoothed version of the
    %   signal to remove the offset, and bandpass filtering if needed
    %   - Automated beat detection
    %   - Manual verification in the GUI
    %
    %   Results and parameters used for the analysis are saved in a .mat
    %   file in the same folder (and optionally as a .csv),
    %   with _HeartBeats added to the original file name.
    %
    %   NB: loading such file allows to modify the previously saved results
    %
    %   The parameters for each step can be changed through the GUI which
    %   allows to easily adjust them. Beats correction is easy, via simple
    %   clicking.
    %
    %   Default parameters are different depending on the species.
    %   The species can be specified in the call    
    %       e.g. ECG_Process('Rat')
    %   or changed in the default parameters of the class, then just
    %   calling as ECG_Process
    %   
    %   NB: supported formats are so far normal text files, matlab files,
    %   .eeg files, Plexon, NeuraLynx(ncs) and TDT tanks. 
    %
    %   NOTE: the signals are decimated to 1KHz for processing, so the
    %   apparent loss of resolution is normal. The final time stamps are
    %   reevaluated with the full sampling rate.
    %
    % Future implementations/changes:
    %       - tool showing suspicious ranges to be manually checked
    %       - optimization (some operations are slowing down the process 
    %       and could be restricted to subpieces of the signal to speed-up)
    %       - revamping of the metaparameters saving system (e.g. .yaml)
    %
    %     Copyright (C) 2024 Jérémy Signoret-Genest, DefenseCircuitsLab
    %     Original version: 04/12/2019
    %     Current version: 13/10/2024
    %
    %
    %     This program is free software: you can redistribute it and/or modify
    %     it under the terms of the GNU General Public License as published by
    %     the Free Software Foundation, either version 3 of the License, or
    %     (at your option) any later version.
    %
    %     This program is distributed in the hope that it will be useful,
    %     but WITHOUT ANY WARRANTY; without even the implied warranty of
    %     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    %     GNU General Public License for more details.
    %
    %     You should have received a copy of the GNU General Public License
    %     along with this program.  If not, see <https://www.gnu.org/licenses/>.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   EDIT HERE   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%    

    % List of properties to be adjusted depending on the experiments/setup
    properties(SetAccess = private, GetAccess = public, Hidden = false)
        PowerGrid = 50; % Frequency of the main hum (e.g. 50Hz for Europe, 60Hz for US)
        Species = 'Mouse'; % Default species: 'Mouse', 'Rat' or 'Human'
    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   




%%%%%%%%%%%%%%%%%%%%%%%%%%%  DO NOT EDIT BELOW  %%%%%%%%%%%%%%%%%%%%%%%%%%%  

    % List of properties directly visible from the object
    properties(SetAccess = private, GetAccess = public, Hidden = false)
        % Visual aspects
        Scaling

        % Interactivity
        Extensions = {'pl2','csv','eeg','txt','mat','tev','ncs'};
        ExtensionFilter = '*.pl2;*.csv;*.eeg;*.txt;*.mat;*_Denoised.mat;*tev;*.ncs';

        % Files
        Basename
        Ext
        Path
        HeartBeatsFile
        LogFile
        RawFile
        StartPath

        % Processing
        Artefacts
        Frequency
        HeartBeats
        HeartRate
        MaxCorr
        MaxNaNRange = 0.005; % Maximum duration (in s) of NaN ranges to be interpolated
        Parameters
        Peaks
        Preprocessed
        BeatPeaks
        RangeShapes
        RemovedWindows
        Shapes
        RawValues
        RawFrequency
        RawTimes
        Template
        Times
    end


    % List of properties hidden and only accessible for dev/debugging
    properties(SetAccess = private, GetAccess = public, Hidden = true)
        % GUI
        Axes
        Colors
        Figure
        Handles

        % Interactivity


        Elevated
        SubHR
        SubPeaks
        SubRaw

        DefaultParameters
        Display
        Dragging
        IndxRmv
        LastFailed
        PartialReloadMode
        Previous
        ReloadMode
        Selected
        Scrolling = false;
        Slider

        CurrVer = 240924;
        LegacyMode = false;
    end


    methods
        % Constructor
        function obj = ECG_Process(varargin)
            obj.Colors = DefColors;
            %% Parameters sets (valid for our acquisition systems, can be tuned differently)
            obj.Parameters.Default.Rat = struct(...
                'ArtefactsDetectSmoothing',26,...
                'AutoUpdate',true,...
                'AutoArtefactsRemoval',true,...
                'BeatPeaksEnable', false,...
                'BeatPeaksFilter', true,...
                'BPEnable',true,...
                'BPHigh', 400,...
                'BPLow', 60,...
                'Channel',[],...
                'DeDriftEnable',0,...
                'DeDriftKernel', 1,...
                'Discontinue', 1,...
                'ExportCSVHeartbeats',false,...
                'ExportCSVHR',false,...
                'ncs_ExternalFrag',false,...
                'InverseECG',false,...
                'NotchFilter', false,...
                'Outlier', 50,...
                'PassNumber',2,...
                'Power', 4,...
                'PeakRange', 8,...
                'ProcessingSamplingRate',1000,... % Target sampling rate for the ECG during the analyses (downsampled to speed up and homogenize parameters)
                'ShapesEnable', false,...
                'SlidingWindowSize', 1,...
                'SmoothDetection', 5,...
                'Species','Rat',...
                'StableIndex', 8,...
                'SuspiciousFrequencyHigh', 12,...
                'SuspiciousFrequencyLow', 6,...
                'Threshold', 1e5,...
                'Unit','bpm',...
                'WaveformWindowLow', -20,...
                'WaveformWindowHigh', 20);

            obj.Parameters.Default.Mouse = struct(...
                'ArtefactsDetectSmoothing',16,...
                'AutoUpdate',true,...
                'AutoArtefactsRemoval',true,...
                'BeatPeaksEnable', false,...
                'BeatPeaksFilter', true,...
                'BPEnable',true,...
                'BPHigh', 180,...
                'BPLow', 60,...
                'Channel',[],...
                'DeDriftEnable',0,...
                'DeDriftKernel', 1,...
                'Discontinue', 1,...
                'ExportCSVHeartbeats',false,...
                'ExportCSVHR',false,...
                'ncs_ExternalFrag',false,...
                'InverseECG',false,...
                'NotchFilter', false,...
                'Outlier', 30,...
                'PassNumber',2,...
                'Power', 4,...
                'PeakRange', 4,...
                'ProcessingSamplingRate',1000,... % Target sampling rate for the ECG during the analyses (downsampled to speed up and homogenize parameters)
                'ShapesEnable', false,...
                'SlidingWindowSize', 0.6,...
                'SmoothDetection', 3,...
                'Species','Mouse',...
                'StableIndex', 5,...
                'SuspiciousFrequencyHigh', 15,...
                'SuspiciousFrequencyLow', 8,...
                'Threshold', 1e5,...
                'Unit','bpm',...
                'WaveformWindowLow', -15 ,...
                'WaveformWindowHigh', 15);


            obj.Parameters.Default.Human = struct(...
                'ArtefactsDetectSmoothing',180,...
                'AutoUpdate',true,...
                'AutoArtefactsRemoval',true,...
                'BeatPeaksEnable', false,...
                'BeatPeaksFilter', true,...
                'BPEnable',true,...
                'BPHigh', 180,...
                'BPLow', 1,...
                'Channel',[],...
                'DeDriftEnable',false,...
                'DeDriftKernel', 10,...
                'Discontinue',4,...
                'ExportCSVHeartbeats',false,...
                'ExportCSVHR',false,...
                'ncs_ExternalFrag',false,...
                'InverseECG',false,...
                'NotchFilter', true,...
                'Outlier', 240,...
                'PassNumber',2,...
                'ProcessingSamplingRate',1000,...
                'Power', 4,...
                'PeakRange', 40,...
                'ShapesEnable', false,...
                'SlidingWindowSize', 5,...
                'SmoothDetection', 35,...
                'Species','Human',...
                'StableIndex', 50,...
                'SuspiciousFrequencyHigh', 2,...
                'SuspiciousFrequencyLow', 1,...
                'Threshold', 1e36,...
                'Unit','bpm',...
                'WaveformWindowLow', -75 ,...
                'WaveformWindowHigh', 75);

            % Set species
            Species = fieldnames(obj.Parameters.Default);
            if ~isempty(varargin)
                if ~(numel(varargin)==1 && (ischar(varargin{1}) || isstring(varargin{1})) && numel(varargin{1})==1 && any(strcmpi(Species,varargin{1})))
                    Species = varargin{1};
                else
                    error(['The only input allowed for ECG_Process is a valid species: ' newline...
                    '''' strjoin(Species, ''', ''') '''.']);
                end
            else
                % Set to default
                Species = obj.Species;
            end
            obj.RestoreDefault(Species);

            %% Make sure that the GUI has access to the SDKs
            currentFile = mfilename('fullpath');
            [currentFolder, ~, ~] = fileparts(currentFile);
            addpath(genpath(currentFolder))

            %% Prepare the GUI
            % Create the figure based on the screen specs
            set(0,'Units','pixels')
            Scrsz = get(0,'ScreenSize');
            obj.Figure = figure('Position', [0 45 Scrsz(3) Scrsz(4) - 45], ...
                'MenuBar', 'none', ...
                'ToolBar', 'figure', ...
                'Renderer', 'painters');
            obj.Figure.WindowState = 'maximized'; % deals with windows taskbar so better than guessing the position

            % Get a scaling factor for font and UI linewidth based on screen size
            obj.Scaling = min([Scrsz(3) / 1920, Scrsz(4) / 1080]);

            % Create the plotting axes
            obj.Axes.SubRaw = axes('Position', [0.06 0.075 0.65 0.15]);
            obj.Axes.Elevated = axes('Position', [0.06 0.23 0.65 0.15]);
            obj.Axes.SubPeaks = axes('Position', [0.06 0.385 0.65 0.35]);
            obj.Axes.SubHR = axes('Position', [0.06 0.74 0.65 0.225]);
            obj.Axes.Slider = axes('Position', [0.06 0.97 0.65 0.025], ...
                'Interactions', [], ...
                'PickableParts', 'none');
            hold(obj.Axes.Slider, 'on');
            obj.Axes.Slider.YLim = [0 1];

            if ~verLessThan('matlab', '9.5')
                obj.Axes.Slider.Toolbar.Visible = 'off';
                disableDefaultInteractivity(obj.Axes.Slider);
            end

            obj.Handles.SliderLine = plot([10 10], [0 1], ...
                'Color', 'k', ...
                'LineWidth', ceil(obj.Scaling * 3.5), ...
                'ButtonDownFcn', {@(~,~)obj.Axes.SliderCB}, ...
                'Parent', obj.Axes.Slider);

            set(obj.Axes.Slider,...
                'Color','w',...
                'YColor','none',...
                'XColor','none')

            % Link the X limits of these axes
            linkaxes([obj.Axes.SubRaw, obj.Axes.Elevated, obj.Axes.SubPeaks, obj.Axes.SubHR], 'x');

            UIBox(1) = axes('Position', [0.72 0.075 0.25 0.125], ...
                'Interactions', [], ...
                'PickableParts', 'none');

            UIBox(2) = axes('Position', [0.72 0.23 0.25 0.125], ...
                'Interactions', [], ...
                'PickableParts', 'none');

            plot([0.7575 0.7575], [0 1], ...
                'k--', ...
                'LineWidth', 1.5, ...
                'Parent', UIBox(2));

            set(UIBox(2),...
                'XLimMode','Manual',...
                'YLimMode','Manual',...
                'XLim',[0 1],...
                'YLim',[0 1]);

            UIBox(3) = subplot('Position', [0.72 0.385 0.25 0.325], ...
                'Interactions', [], ...
                'PickableParts', 'none');

            UIBox(4) = subplot('Position', [0.72 0.74 0.25 0.225], ...
                'Interactions', [], ...
                'PickableParts', 'none');

            set([UIBox(:)], ...
                'Box', 'on', ...
                'XTick', [], ...
                'YTick', [], ...
                'LineWidth', ceil(obj.Scaling*2));

            % Add titles to the parameters boxes
            uicontrol('Style', 'pushbutton', ...
                'String', 'Pre-processing', ...
                'FontSize', obj.Scaling*14, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.72+0.075 0.185 0.1 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w', ...
                'Enable', 'inactive');
            uicontrol('Style', 'pushbutton', ...
                'String', 'Detection', ...
                'FontSize', obj.Scaling*14, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.72+0.075 0.34 0.1 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w', ...
                'Enable', 'inactive');
            uicontrol('Style', 'pushbutton', ...
                'String', 'Corrections', ...
                'FontSize', obj.Scaling*14, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.72+0.075 0.695 0.1 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w', ...
                'Enable', 'inactive');
            uicontrol('Style', 'pushbutton', ...
                'String', 'Heart rate', ...
                'FontSize', obj.Scaling*14, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.72+0.075 0.95 0.1 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w', ...
                'Enable', 'inactive');

            % Initialize current file name display
            obj.Handles.CurrentFile = uicontrol('Style', 'text', ...
                'String', '', ...
                'FontSize', obj.Scaling*14, ...
                'FontName', 'Arial', ...
                'FontWeight', 'normal', ...
                'Units', 'Normalized', ...
                'Position', [0.72 0.04 0.25 0.03], ...
                'HorizontalAlignment', 'left');

            % Pre-processing UI elements and callbacks
            obj.Handles.DeDrift_CheckBox = uicontrol('Style', 'checkbox', ...
                'String', ' Drift estimation', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.DeDriftEnableCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.73 0.145 0.12 0.03], ...
                'BackgroundColor', 'w', ...
                'Value', obj.Parameters.Current.DeDriftEnable);
            uicontrol('Style', 'text', ...
                'String',  'Window (s)', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.835 0.14 0.06 0.03], ...
                'HorizontalAlignment', 'right', ...
                'BackgroundColor', 'w');
            obj.Handles.BandPass_CheckBox = uicontrol('Style', 'checkbox', ...
                'String', ' Bandpass filtering', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.BPEnableCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.75 0.105 0.12 0.03], ...
                'BackgroundColor', 'w', ...
                'Value', obj.Parameters.Current.BPEnable);
            uicontrol('Style', 'text', ...
                'String', 'Low', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.87 0.105 0.04 0.03], ...
                'HorizontalAlignment', 'left', ...
                'BackgroundColor', 'w');
            uicontrol('Style', 'text', ...
                'String', 'High', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.87 0.075 0.04 0.03], ...
                'HorizontalAlignment', 'left', ...
                'BackgroundColor', 'w');
            obj.Handles.BPHigh.Edit = uicontrol('Style', 'edit', ...
                'String', obj.Parameters.Current.BPHigh, ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.BPHighEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.9 0.08 0.04 0.03], ...
                'HorizontalAlignment', 'center');
            obj.Handles.BPLow.Edit = uicontrol('Style', 'edit', ...
                'String', obj.Parameters.Current.BPLow, ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.BPLowEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.9 0.11 0.04 0.03], ...
                'HorizontalAlignment', 'center');
            obj.Handles.InverseECG_CheckBox = uicontrol('Style', 'checkbox', ...
                'String', ' Flip signal', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.InverseECGCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.73 0.075 0.12 0.03], ...
                'BackgroundColor', 'w', ...
                'Value', obj.Parameters.Current.InverseECG);
            obj.Handles.DeDriftKernel.Edit = uicontrol('Style', 'edit', ...
                'String', obj.Parameters.Current.DeDriftKernel, ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.DeDriftKernelEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.9 0.145 0.04 0.03], ...
                'HorizontalAlignment', 'center');
            % NB: all the "Set" buttons are in theory useless, but since
            % the callbacks for the edit boxes are executed only when
            % clicking outside, this prevents any over-questioning
            obj.Handles.DeDriftKernel.Set = uicontrol('Style', 'pushbutton', ...
                'String', 'Set', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.DeDriftKernelEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.94 0.145 0.025 0.03], ...
                'HorizontalAlignment', 'center');
            obj.Handles.BPSet = uicontrol('Style', 'pushbutton', ...
                'String', 'Set', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.BPSetCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.94 0.095 0.025 0.03], ...
                'HorizontalAlignment', 'center');

            % Detection UI elements and callbacks
            uicontrol('Style', 'text', ...
                'String', 'Power', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.73 0.295 0.065 0.03], ...
                'HorizontalAlignment', 'right', ...
                'BackgroundColor', 'w');

            uicontrol('Style', 'text', ...
                'String', 'Threshold', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.73 0.265 0.065 0.03], ...
                'HorizontalAlignment', 'right', ...
                'BackgroundColor', 'w');

            uicontrol('Style', 'text', ...
                'String', 'Smoothing', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.73 0.235 0.065 0.03], ...
                'HorizontalAlignment', 'right', ...
                'BackgroundColor', 'w');

            uicontrol('Style', 'text', ...
                'String', 'Window', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.915 0.295 0.05 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

            obj.Handles.Power.Edit = uicontrol('Style', 'edit', ...
                'String', num2str(obj.Parameters.Current.Power), ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.PowerEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.8 0.2975 0.04 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

            obj.Handles.Threshold.Edit = uicontrol('Style', 'edit', ...
                'String', num2str(obj.Parameters.Current.Threshold, 3), ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.ThresholdEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.8 0.2675 0.065 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

            obj.Handles.SmoothDetection.Edit = uicontrol('Style', 'edit', ...
                'String', num2str(obj.Parameters.Current.SmoothDetection), ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.SmoothDetectionEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.8 0.2375 0.04 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

            obj.Handles.WaveformWindowLow.Edit = uicontrol('Style', 'edit', ...
                'String', num2str(obj.Parameters.Current.WaveformWindowLow), ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.WaveformWindowLowEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.915 0.2675 0.025 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

            obj.Handles.WaveformWindowHigh.Edit = uicontrol('Style', 'edit', ...
                'String', num2str(obj.Parameters.Current.WaveformWindowHigh), ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.WaveformWindowHighEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.94 0.2675 0.025 0.03], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

            obj.Handles.Power.Set = uicontrol('Style', 'pushbutton', ...
                'String', 'Set', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.PowerEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.84 0.2975 0.025 0.03], ...
                'HorizontalAlignment', 'center');

            obj.Handles.Threshold.Set = uicontrol('Style', 'pushbutton', ...
                'String', 'Set', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.ThresholdSetCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.865 0.2675 0.025 0.03], ...
                'HorizontalAlignment', 'center');

            obj.Handles.SmoothDetection.Set = uicontrol('Style', 'pushbutton', ...
                'String', 'Set', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.SmoothDetectionEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.84 0.2375 0.025 0.03], ...
                'HorizontalAlignment', 'center');

            obj.Handles.WindowLH.Set = uicontrol('Style', 'pushbutton', ...
                'String', 'Set', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.WindowLHSetCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.9275 0.2375 0.025 0.03], ...
                'HorizontalAlignment', 'center');

            % Manual interventions UI elements and callbacks
            DCol = DefColors;

            obj.Handles.StartPath = uicontrol('Style', 'pushbutton', ...
                'String', 'Start Path', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.StartPathCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.725 0.395 0.06 0.04], ...
                'HorizontalAlignment', 'center');

            obj.Handles.Load = uicontrol('Style', 'pushbutton', ...
                'String', 'Load file', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.LoadCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.785 0.395 0.06 0.04], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', DCol(2,:) + 0.1);

            obj.Handles.Save = uicontrol('Style', 'pushbutton', ...
                'String', 'Save', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.SaveCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.845 0.395 0.06 0.04], ...
                'HorizontalAlignment', 'center');

            obj.Handles.Exit = uicontrol('Style', 'pushbutton', ...
                'String', 'Exit', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.ExitCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.905 0.395 0.06 0.04], ...
                'HorizontalAlignment', 'center');
            
            ExportCSVHeader = uicontrol('Style', 'text', ...
                'String', ['Export as .csv:' newline '(optional)'], ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.725 0.485 0.10 0.075], ...
                'HorizontalAlignment', 'left', ...
                'BackgroundColor', 'w');

            obj.Handles.ExportCSVHeartbeats = uicontrol('Style', 'checkbox', ...
                'String', ' Heartbeats', ...
                'FontSize', obj.Scaling*14, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.ExportCSVHeartbeatsCB}, ...
                'Value', obj.Parameters.Current.ExportCSVHeartbeats,...
                'Units', 'Normalized', ...
                'Position', [0.74 0.47 0.12 0.04], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

            obj.Handles.ExportCSVHR = uicontrol('Style', 'checkbox', ...
                'String', ' Heart rate', ...
                'FontSize', obj.Scaling*14, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.ExportCSVHRCB}, ...
                'Value', obj.Parameters.Current.ExportCSVHR,...
                'Units', 'Normalized', ...
                'Position', [0.74 0.44 0.12 0.04], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

%             obj.Handles.LockX = uicontrol('Style', 'checkbox', ...
%                 'String', 'Lock X axes', ...
%                 'FontSize', obj.Scaling*16, ...
%                 'FontName', 'Arial', ...
%                 'FontWeight', 'bold', ...
%                 'Callback', {@(~,~)obj.LockXCB}, ...
%                 'Units', 'Normalized', ...
%                 'Position', [0.725 0.52 0.12 0.04], ...
%                 'HorizontalAlignment', 'center', ...
%                 'BackgroundColor', 'w');
% 
%             obj.Handles.LockY = uicontrol('Style', 'checkbox', ...
%                 'String', 'Lock Y axes', ...
%                 'FontSize', obj.Scaling*16, ...
%                 'FontName', 'Arial', ...
%                 'FontWeight', 'bold', ...
%                 'Callback', {@(~,~)obj.LockYCB}, ...
%                 'Units', 'Normalized', ...
%                 'Position', [0.725 0.47 0.12 0.04], ...
%                 'HorizontalAlignment', 'center', ...
%                 'BackgroundColor', 'w');

            obj.Handles.EnableShapes = uicontrol('Style', 'checkbox', ...
                'String', 'Plot waveforms', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.EnableShapesCB}, ...
                'Value', obj.Parameters.Current.ShapesEnable, ...
                'Units', 'Normalized', ...
                'Position', [0.725 0.57 0.12 0.04], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

            obj.Handles.BeatPeaksEnable = uicontrol('Style', 'checkbox', ...
                'String', 'Plot peak', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.BeatPeaksEnableCB}, ...
                'Value', obj.Parameters.Current.BeatPeaksEnable, ...
                'Units', 'Normalized', ...
                'Position', [0.725 0.62 0.12 0.04], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', 'w');

            obj.Handles.Process = uicontrol('Style', 'pushbutton', ...
                'String', 'Run algorithm', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.ProcessCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.845 0.62 0.12 0.04], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', DCol(1,:) + 0.1);


            uicontrol('Style', 'text', ...
                'String', 'Passes', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.835 0.5725-0.0025 0.075 0.03], ...
                'HorizontalAlignment', 'right', ...
                'BackgroundColor', 'w');

            obj.Handles.PassesNumber.Edit = uicontrol('Style', 'edit', ...
                'String', num2str(obj.Parameters.Current.PassNumber), ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.PassesNumberCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.845+0.0725 0.5725 0.04 0.03], ...
                'HorizontalAlignment', 'center');


            obj.Handles.AddRange = uicontrol('Style', 'pushbutton', ...
                'String', 'Add exclusion range', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.AddRangeCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.845 0.52 0.12 0.04], ...
                'HorizontalAlignment', 'center');

            obj.Handles.DeleteRange = uicontrol('Style', 'pushbutton', ...
                'String', 'Delete selected range', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.DeleteRangeCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.845 0.47 0.12 0.04], ...
                'HorizontalAlignment', 'center');

            % Heart rate UI elements and callbacks
            uicontrol('Style', 'text', ...
                'String', 'Window size', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.7275 0.8875 0.07 0.03], ...
                'HorizontalAlignment', 'right', ...
                'BackgroundColor', 'w');

            obj.Handles.SlidingWindowSize.Edit = uicontrol('Style', 'edit', ...
                'String', obj.Parameters.Current.SlidingWindowSize, ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.SlidingWindowSizeEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.80 0.89 0.04 0.03], ...
                'HorizontalAlignment', 'center');

            obj.Handles.SlidingWindowSize.Set = uicontrol('Style', 'pushbutton', ...
                'String', 'Set', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.SlidingWindowSizeEditCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.84 0.89 0.025 0.03], ...
                'HorizontalAlignment', 'center');

            obj.Handles.AutoUpdateHR = uicontrol('Style', 'checkbox', ...
                'String', ' AutoUpdate', ...
                'FontSize', obj.Scaling*12, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.AutoUpdateHRCB}, ...
                'Value', obj.Parameters.Current.AutoUpdate, ...
                'Units', 'Normalized', ...
                'Position', [0.905 0.855 0.06 0.04], ...
                'BackgroundColor', 'w');

            obj.Handles.UpdateHeartRate = uicontrol('Style', 'pushbutton', ...
                'String', 'Update', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.ProcessHeartRate}, ...
                'Units', 'Normalized', ...
                'Position', [0.905 0.885 0.06 0.04], ...
                'HorizontalAlignment', 'center');

            uicontrol('Style', 'text', ...
                'String', 'Unit', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Units', 'Normalized', ...
                'Position', [0.73125 0.83 0.04 0.03], ...
                'HorizontalAlignment', 'left', ...
                'BackgroundColor', 'w');

            obj.Handles.BPM = uicontrol('Style', 'checkbox', ...
                'String', ' Beats per minute (bpm)', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.BPMCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.77 0.83 0.15 0.03], ...
                'BackgroundColor', 'w');

            obj.Handles.Hz = uicontrol('Style', 'checkbox', ...
                'String', ' Beats per second (Hz)', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.HzCB}, ...
                'Units', 'Normalized', ...
                'Position', [0.77 0.79 0.15 0.03], ...
                'BackgroundColor', 'w');

            obj.Handles.RestoreView = uicontrol('Style', 'pushbutton', ...
                'String', 'Restore view', ...
                'FontSize', obj.Scaling*16, ...
                'FontName', 'Arial', ...
                'FontWeight', 'bold', ...
                'Callback', {@(~,~)obj.RestoreView}, ...
                'Units', 'Normalized', ...
                'Position', [0.73 0.745 0.075 0.04], ...
                'HorizontalAlignment', 'center');

            if strcmpi(obj.Parameters.Current.Unit,'bpm')
                obj.Handles.BPM.Value = 1;
            else
                obj.Handles.Hz.Value = 1;
            end

            % Prepare zoom in case we want to limit it to X axes
            obj.Handles.ZoomElevated = zoom(obj.Axes.Elevated);
            obj.Handles.ZoomSubHR.Motion = zoom(obj.Axes.SubHR);
            obj.Handles.ZoomSubPeaks.Motion = zoom(obj.Axes.SubPeaks);
            obj.Handles.ZoomSubRaw.Motion = zoom(obj.Axes.SubRaw);
            obj.Handles.ZoomSubHR.Motion.ActionPostCallback = @(~,~)obj.EvaluateWindow;
            obj.Handles.ZoomSubPeaks.Motion.ActionPostCallback = @(~,~)obj.EvaluateWindow;
            obj.Handles.ZoomSubRaw.Motion.ActionPostCallback = @(~,~)obj.EvaluateWindow;
            obj.Handles.ZoomSubHR.Motion.ActionPostCallback = @(~,~)obj.EvaluateWindow;

            % Set data axes aspects
            obj.SubplotVisual;
            drawnow

            % Disable all callbacks
            obj.DisableAll;

            % Re-enable only the basic ones first
            obj.Handles.Load.Enable = 'on';
            obj.Handles.StartPath.Enable = 'on';
            obj.Handles.Exit.Enable = 'on';
        end
    end

    methods(Hidden)
        function RestoreDefault(obj,Species)
            obj.Parameters.Current = obj.Parameters.Default.(Species);
            obj.ApplyParameters;
        end

        function ApplyParameters(obj)
            % Apply for values from the parameters list to the UI elements
            obj.Handles.BandPass_CheckBox.Value = obj.Parameters.Current.BPEnable;
            obj.Handles.DeDrift_CheckBox.Value = obj.Parameters.Current.DeDriftEnable;
            obj.Handles.BPHigh.Edit.String = num2str(obj.Parameters.Current.BPHigh);
            obj.Handles.BPLow.Edit.String = num2str(obj.Parameters.Current.BPLow);
            obj.Handles.EnableShapes.Value = obj.Parameters.Current.ShapesEnable;
            obj.Handles.Power.Edit.String = num2str(obj.Parameters.Current.Power);
            obj.Handles.SlidingWindowSize.Edit.String = num2str(obj.Parameters.Current.SlidingWindowSize);
            obj.Handles.DeDriftKernel.Edit.String = num2str(obj.Parameters.Current.DeDriftKernel);
            obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Current.Threshold,3);
            obj.Handles.AutoUpdateHR.Value = obj.Parameters.Current.AutoUpdate;
            obj.Handles.SmoothDetection.Edit.String = num2str(obj.Parameters.Current.SmoothDetection);
            obj.Handles.WaveformWindowLow.Edit.String = num2str(obj.Parameters.Current.WaveformWindowLow);
            obj.Handles.WaveformWindowHigh.Edit.String = num2str(obj.Parameters.Current.WaveformWindowHigh);
        end

        function SubplotVisual(obj)
            % (Re)set data axes aspects
            obj.Axes.SubRaw.LineWidth = 2*obj.Scaling;
            obj.Axes.SubRaw.FontSize = 12*obj.Scaling;
            obj.Axes.SubRaw.FontWeight = 'b';
            obj.Axes.SubRaw.TickDir = 'out';
            obj.Axes.SubRaw.XLabel.String = 'Time (s)';
            obj.Axes.SubRaw.XLabel.FontSize = 17*obj.Scaling;
            obj.Axes.SubRaw.YLabel.String = 'Raw ECG';
            obj.Axes.SubRaw.YLabel.FontSize = 17;
            obj.Axes.SubRaw.YTick = [];
            obj.Axes.SubRaw.Box = 'off';

            obj.Axes.Elevated.LineWidth = 2*obj.Scaling;
            obj.Axes.Elevated.XColor = 'none';
            obj.Axes.Elevated.YLabel.String = 'Elevated ECG';
            obj.Axes.Elevated.FontSize = 12*obj.Scaling;
            obj.Axes.Elevated.FontWeight = 'b';
            obj.Axes.Elevated.TickDir = 'out';
            obj.Axes.Elevated.YLabel.FontSize = 17*obj.Scaling;
            obj.Axes.Elevated.YTick = [];
            obj.Axes.Elevated.Box = 'off';

            obj.Axes.SubPeaks.LineWidth = 2*obj.Scaling;
            obj.Axes.SubPeaks.XColor = 'none';
            obj.Axes.SubPeaks.YLabel.String = 'ECG';
            obj.Axes.SubPeaks.FontSize = 12*obj.Scaling;
            obj.Axes.SubPeaks.FontWeight = 'b';
            obj.Axes.SubPeaks.TickDir = 'out';
            obj.Axes.SubPeaks.YLabel.FontSize = 17*obj.Scaling;
            obj.Axes.SubPeaks.YTick = [];
            obj.Axes.SubPeaks.Box = 'off';

            obj.Axes.SubHR.LineWidth = 2*obj.Scaling;
            obj.Axes.SubHR.XColor = 'none';
            if strcmpi(obj.Parameters.Current.Unit,'bpm')
                obj.Axes.SubHR.YLabel.String = 'Heart rate (bpm)';
            else
                obj.Axes.SubHR.YLabel.String = 'Heart rate (Hz)';
            end
            obj.Axes.SubHR.FontSize = 12*obj.Scaling;
            obj.Axes.SubHR.FontWeight = 'b';
            obj.Axes.SubHR.TickDir = 'out';
            obj.Axes.SubHR.YLabel.FontSize = 17*obj.Scaling;
            obj.Axes.SubHR.Box = 'off';

            if ~isempty(obj.Times)
                if obj.Axes.SubHR.XLim(2)>obj.Times(end)
                    obj.Axes.SubHR.XLim(2) = obj.Times(end);
                end
            end

            % Add keypress listeners
            obj.Figure.KeyPressFcn = {@(Src,Key)obj.KeyPressCB(Src,Key)};
            drawnow
        end

        function RestoreView(obj)
            % Restore full view
            if ~isempty(obj.Times)
                obj.Axes.SubHR.XLim = obj.Times([1 end]);
                AxTemp = {'SubHR','SubRaw','SubPeaks'};
                for AT = 1 : numel(AxTemp)
                    set(obj.Axes.(AxTemp{AT}),...
                        'YLimMode','manual',...
                        'YLim',[obj.Handles.Min.(AxTemp{AT}) obj.Handles.Max.(AxTemp{AT})]);
                end
                obj.Axes.Elevated.YLimMode = 'auto';
                drawnow
            end
        end

        function KeyPressCB(obj,~,Key)
            if ~obj.Scrolling
                obj.Scrolling = true;
                if strcmpi(Key.Key,'rightarrow')
                    if (obj.Axes.SubHR.XLim(2) + 0.25*diff(obj.Axes.SubHR.XLim))<=obj.Times(end)
                        obj.Axes.SubHR.XLim = obj.Axes.SubHR.XLim + 0.25*diff(obj.Axes.SubHR.XLim);
                        obj.Handles.SliderLine.XData = [1 1] * obj.Axes.SubHR.XLim(1) + 0.5*diff(obj.Axes.SubHR.XLim);
                    else
                        obj.Axes.SubHR.XLim = [obj.Times(end)-diff(obj.Axes.SubHR.XLim) obj.Times(end)];
                        obj.Handles.SliderLine.XData = [1 1] * obj.Axes.SubHR.XLim(1);
                    end
                elseif strcmpi(Key.Key,'leftarrow')
                    if (obj.Axes.SubHR.XLim(1) - 0.25*diff(obj.Axes.SubHR.XLim))>=obj.Times(1)
                        obj.Axes.SubHR.XLim = obj.Axes.SubHR.XLim - 0.25*diff(obj.Axes.SubHR.XLim);
                        obj.Handles.SliderLine.XData = [1 1] * obj.Axes.SubHR.XLim(1) + 0.5*diff(obj.Axes.SubHR.XLim);
                    else
                        obj.Axes.SubHR.XLim = [obj.Times(1) obj.Times(1)+diff(obj.Axes.SubHR.XLim)];
                        obj.Handles.SliderLine.XData = [1 1] * obj.Axes.SubHR.XLim(2);
                    end
                end
                drawnow;
                obj.Scrolling = false;
            end
        end

        function LoadCB(obj)
            % Disable interactions
            obj.DisableAll;

            % Prompt to choose a file:
            %    - _HeartBeats.mat for previously processed session
            %    - any supported format for ECG (can be easily expanded)
            [File,Path] = uigetfile({[obj.StartPath '*_HeartBeats.mat;' obj.ExtensionFilter]},'Please select a file to process.');
            if File == 0 % No file was selected
                if isempty(obj.RawFile)
                    obj.Handles.Load.Enable = 'on';
                    obj.Handles.StartPath.Enable = 'on';
                    obj.Handles.Exit.Enable = 'on';
                else
                    obj.EnableAll;
                end
                return
            end
            % Retrieve basename and extension for the file
            [~,Basename,Ext] = fileparts(File);
            TempReloadMode = false;
            if contains(File,'_HeartBeats.mat')
                Basename = strsplit(Basename,'_HeartBeats');
                Basename = Basename{1};

                % Check that we have the metadata file
                TempLogFile = fullfile(Path,[Basename '_ECGLog.mat']);
                if exist(TempLogFile,'file')~=2
                    Wn = warndlg(['No matching ECG_Process metadata file found for the session.' newline 'Aborting.']);
                    waitfor(Wn)
                    obj.EnableAll;
                    return
                else
                    % Read the file to find the raw ECG file name / type
                    Loaded_LogFile = load(TempLogFile);
                    if isfield(Loaded_LogFile,'Files')
                        TempRawFile = Loaded_LogFile.Files.RawECG_File;
                        Ext = [Loaded_LogFile.Files.RawECG_FileType];
                    else
                        % Legacy
                        FileFound = false;
                        for FileExt = 1 : numel(obj.Extensions)
                            if ~strcmpi(obj.Extensions{FileExt},'mat')
                                TempRawFile = fullfile(Path,[Basename '.' obj.Extensions{FileExt}]);
                                Ext = ['.' obj.Extensions{FileExt}];
                                if isfile(TempRawFile)
                                    FileFound = true;
                                    break
                                end
                            end
                        end
                        if ~FileFound
                            Wn = warndlg(['No matching raw ECG file found for the session.' newline 'Aborting.']);
                            waitfor(Wn)
                            obj.EnableAll;
                            return
                        end
                    end
                    TempReloadMode = true;
                end
                TempHeartBeatsFile = fullfile(Path,File);
            else
                TempRawFile = fullfile(Path,File);
                TempLogFile = fullfile(Path,[Basename '_ECGLog.mat']);
                TempHeartBeatsFile = [Path Basename '_HeartBeats.mat'];
                % First check whether it was processed before
                if exist(TempHeartBeatsFile,'file')==2
                    Answer = questdlg('This file was already processed, do you wish to continue anyway?','Please choose...','Yes (Start again)','Yes (Load previously processed)','No (abort)','Yes (Start again)');
                    waitfor(Answer)
                    if strcmpi(Answer,'No (abort)')
                        obj.EnableAll;
                        return
                    elseif strcmpi(Answer,'Yes (Load previously processed)')
                        % If the heartbeat file is present so should the
                        % logfile... but just in case
                        if exist(TempLogFile,'file')~=2
                            Wn = warndlg(['No matching log file found for the session.' newline 'Default parameters loaded, previous analysis ignored.']);
                            waitfor(Wn)
                        else
                            TempReloadMode = true;
                        end
                    end
                end
            end
            Channel = [];
            Frag = 0;
            switch lower(Ext)
                case '.pl2'
                    % Retrieve channels
                    if TempReloadMode
                        Loaded_LogFile = load(TempLogFile);
                        % Legacy
                        if ~isfield(Loaded_LogFile.Parameters,'Current')
                            ChanPlexon = Loaded_LogFile.Parameters.Channel;
                        else
                            ChanPlexon = Loaded_LogFile.Parameters.Current.Channel;
                        end
                    else
                        Pl2_Index = PL2GetFileIndex(TempRawFile);
                        Analog_Index = arrayfun(@(x) (~(Pl2_Index.AnalogChannels{x}.NumValues == 0)) & strcmpi(Pl2_Index.AnalogChannels{x}.SourceName,'AI'),1:numel(Pl2_Index.AnalogChannels));
                        Analog_Channels = arrayfun(@(x) (Pl2_Index.AnalogChannels{x}.Channel), find(Analog_Index));
                        Analog_Channels = [(find(Analog_Index))',...
                            Pl2_Index.AnalogChannels{find(Analog_Index,1)}.Source * ones(numel(Analog_Channels),1),...
                            Analog_Channels'];

                        % Choose channel
                        [IndexChannel] = listdlg('PromptString','Select the ECG channel to use:',...
                            'SelectionMode','single',...
                            'ListString',num2str(Analog_Channels(:,3)));
                        if isempty(IndexChannel)
                            if isempty(obj.RawFile)
                                obj.Handles.Load.Enable = 'on';
                                obj.Handles.StartPath.Enable = 'on';
                                obj.Handles.Exit.Enable = 'on';
                            else
                                obj.EnableAll;
                            end
                            return
                        else
                            ChanPlexon = Analog_Channels(IndexChannel,1);
                        end
                    end
                    % Load data
                    Channel = ChanPlexon;
                    ECG = PL2Ad(TempRawFile,ChanPlexon);
                    TempRawValues = ECG.Values;
                    TempRawFrequency = ECG.ADFreq;
                    TempRawTimes = ECG.FragTs + ((1 : ECG.FragCounts) / ECG.ADFreq);
                    Frag = ECG.FragTs;
                case '.ncs'
                    Frag = 0;
                    % Optional: use event channel to realign data
                    if ~isempty(obj.Parameters.Current.ncs_ExternalFrag)
                        % Try to find an event file with a similar basename
                        Split_Basename = strsplit(Basename,'_');
                        EventsFile = [Path filesep strjoin(['Events', Split_Basename(2:end)],'_'),'.nev'];
                        if isfile(EventsFile)
                            [Timestamps_tmp,~,Eventstrings_tmp] = Nlx2MatEV(EventsFile,[1 0 1 0 1],0,1,0);
                            % Use custom events to fetch longest recording
                            % in case of multiple bouts
                            StartIdx = find(contains(Eventstrings_tmp,'Starting Recording'));
                            EndIdx = find(contains(Eventstrings_tmp,'Stopping Recording'));
                            % Initialize arrays
                            validStartIdx = [];
                            validEndIdx = [];
                            validDeltas = [];

                            % Loop through all StartIdx and EndIdx
                            for i = 1:length(StartIdx)
                                for j = 1:length(EndIdx)
                                    % Only consider pairs where EndIdx is after StartIdx
                                    if EndIdx(j) > StartIdx(i)
                                        % Store the valid start and end indices
                                        validStartIdx = [validStartIdx, StartIdx(i)];
                                        validEndIdx = [validEndIdx, EndIdx(j)];
                                        % Calculate the delta (duration of the recording)
                                        validDeltas = [validDeltas, EndIdx(j) - StartIdx(i)];
                                    end
                                end
                            end
                            % Now find the maximum delta (longest recording session)
                            [~, MaxIdx] = max(validDeltas);
                            % Extract the corresponding start and end indices for the longest session
                            RecordingStartIdx = validStartIdx(MaxIdx);
                            RecordingEndIdx = validEndIdx(MaxIdx);
                            % Trim the data to the longest valid session
                            AbsTimeRange = Timestamps_tmp([RecordingStartIdx,RecordingEndIdx]);
                        end
                    else
                        AbsTimeRange = [];
                    end
                    % Load data
                    [Timestamps, ~, SampleFrequencies, NumberOfValidSamples, Samples, ~] = Nlx2MatCSC(TempRawFile,ones(1,5),1,1,1);

                    % Adjust ranges if needed
                    if ~isempty(AbsTimeRange)
                        TrimIndx = Timestamps>=AbsTimeRange(1) & Timestamps<=AbsTimeRange(2);
                        Timestamps = Timestamps(TrimIndx);
                        SampleFrequencies = SampleFrequencies(TrimIndx);
                        NumberOfValidSamples = NumberOfValidSamples(TrimIndx);
                        Samples = Samples(:,TrimIndx);
                        Timestamps = (Timestamps-AbsTimeRange(1))/1e6;
                    else
                        Timestamps = (Timestamps-Timestamps(1))/1e6;
                    end

                    % Check frequencies
                    TempRawFrequency = unique(SampleFrequencies);
                    if numel(TempRawFrequency) ~= 1
                        error('Several sampling frequencies found in the file.');
                    end

                    % Files are divided in blocks of N samples
                    nSamplesPerBlock = size(Samples,1);
                    Times_B = ((1:nSamplesPerBlock)/TempRawFrequency)';

                    % Preallocate
                    TempRawValues = nan(numel(Samples),1);
                    TempRawTimes = nan(1,numel(Samples));

                    % Loop to retrieve data
                    FaultyBlocks = 0;
                    Current_Indx = 0;
                    for Block = 1 : size(Samples,2)
                        if NumberOfValidSamples(Block)~=nSamplesPerBlock
                            FaultyBlocks = FaultyBlocks+1;
                            continue
                        end
                        Data_Block = Samples(1 : NumberOfValidSamples(Block),Block);
                        Times_Block = Timestamps(Block) + Times_B(1 : NumberOfValidSamples(Block));
                        TempRawValues(Current_Indx + (1 : NumberOfValidSamples(Block))) = Data_Block;
                        TempRawTimes(Current_Indx + (1 : NumberOfValidSamples(Block))) = Times_Block;
                        Current_Indx = Current_Indx + NumberOfValidSamples(Block)-1;
                    end
                    % Trim/remove NaNs
                    NaNIndx = isnan(TempRawValues);
                    TempRawValues = TempRawValues(~NaNIndx);
                    TempRawTimes = TempRawTimes(~NaNIndx);
                case '.tev'
                    % Retrieve channels
                    if TempReloadMode
                        Loaded_LogFile = load(TempLogFile);
                        % Legacy
                        if ~isfield(Loaded_LogFile.Parameters,'Current')
                            ChanTDT = Loaded_LogFile.Parameters.Channel;
                        else
                            ChanTDT = Loaded_LogFile.Parameters.Current.Channel;
                        end
                        TDTData = TDTbin2mat(Path);
                    else
                        addpath(genpath('F:\MATLAB\Common\SDKs\TDTSDK\'))
                        TDTData = TDTbin2mat(Path);
                        Fields = fields(TDTData.streams);
                        Fields = Fields(contains(Fields,'ECG'));
                        if isempty(Fields)
                            if isempty(obj.RawFile)
                                obj.Handles.Load.Enable = 'on';
                                obj.Handles.StartPath.Enable = 'on';
                                obj.Handles.Exit.Enable = 'on';
                            else
                                obj.EnableAll;
                            end
                            return
                        end

                        % Choose channel
                        [IndexChannel] = listdlg('PromptString','Select the ECG channel to use:',...
                            'SelectionMode','single',...
                            'ListString',Fields);
                        if isempty(IndexChannel)
                            if isempty(obj.RawFile)
                                obj.Handles.Load.Enable = 'on';
                                obj.Handles.StartPath.Enable = 'on';
                                obj.Handles.Exit.Enable = 'on';
                            else
                                obj.EnableAll;
                            end
                            return
                        else
                            ChanTDT = Fields{IndexChannel};
                        end
                    end
                    % Load data
                    Channel = ChanTDT;
                    ECG = TDTData.streams.(Channel);
                    TempRawValues = double(ECG.data)';
                    TempRawFrequency = ECG.fs;
                    TempRawTimes = ECG.startTime + (1 : numel(ECG.data)) / ECG.fs;
                    Frag = ECG.startTime;
                case '.mat'
                    if contains(Basename,'Denoised')
                        % Wireless opto project -denoised ECG
                        RawLoaded = load(TempRawFile);
                        Fields = fieldnames(RawLoaded);
                        if contains(Fields{1},'Chan')
                            if TempReloadMode
                                Loaded_LogFile = load(TempLogFile);
                                if isfield(Loaded_LogFile,'Parameters')  % Legacy
                                    Channel = Loaded_LogFile.Parameters.Channel;
                                elseif isfield(Loaded_LogFile,'Channel')
                                    Channel = Loaded_LogFile.Channel;
                                end
                                IndexChannel = find(contains(Fields,num2str(Channel)));
                            else
                                if numel(Fields)>1
                                    [IndexChannel] = listdlg('PromptString','Select the ECG channel to use:',...
                                        'SelectionMode','single',...
                                        'ListString',Fields);
                                else
                                    IndexChannel = 1;
                                end
                                if isempty(IndexChannel)
                                    if isempty(obj.RawFile)
                                        obj.Handles.Load.Enable = 'on';
                                        obj.Handles.StartPath.Enable = 'on';
                                        obj.Handles.Exit.Enable = 'on';
                                    else
                                        obj.EnableAll;
                                    end
                                    return
                                else
                                    Channel = str2double(strrep(Fields{IndexChannel},'Chan',''));
                                end
                            end
                            TempRawValues = RawLoaded.(Fields{IndexChannel}).Values;
                            TempRawTimes = RawLoaded.(Fields{IndexChannel}).Times;
                            TempRawFrequency = RawLoaded.(Fields{IndexChannel}).Frequency;
                        else
                            % Old version, only one channel
                            TempRawValues = RawLoaded.Values;
                            TempRawTimes = RawLoaded.Times;
                            TempRawFrequency = RawLoaded.Frequency;
                        end
                    else
                        % Check that we have a timestamps and values array
                        % (first column being timestamps, the others being
                        % "channels")
                        RawLoaded = load(TempRawFile);
                        ValidFile = false;
                        if (ismatrix(RawLoaded) && all(isnumeric(RawLoaded),'all'))
                            if (size(RawLoaded,2)>1 && size(RawLoaded,1)>=10) % At least 10 values to make sure we have the right orientation
                                Time_diff = diff(RawLoaded(:,1));
                                Tolerance = 1e-6;
                                if all(abs(Time_diff - mean(Time_diff)) < Tolerance) && all(Time_diff>0)
                                    ValidFile = true;
                                end
                            end
                        end
                        if ~ValidFile
                            Wn = warndlg(['The file does not contain a valid ECG signal as [TimeStamps, Channel1_Values,..., Channeln_Values].'...
                                newline 'Aborting.']);
                            waitfor(Wn)
                            obj.EnableAll;
                            return
                        else
                            if TempReloadMode
                                Loaded_LogFile = load(TempLogFile);
                                % Legacy
                                if ~isfield(Loaded_LogFile.Parameters,'Current')
                                    Channel = Loaded_LogFile.Parameters.Channel;
                                else
                                    Channel = Loaded_LogFile.Parameters.Current.Channel;
                                end
                            else
                                if size(RawLoaded,2)>2
                                    [IndexChannel] = listdlg('PromptString','Select the ECG channel to use:',...
                                        'SelectionMode','single',...
                                        'ListString',string(1:(size(RawLoaded,2)-1)));
                                    IndexChannel = str2double(IndexChannel) + 1;
                                else
                                    IndexChannel = 2;
                                end
                                if isnan(IndexChannel) || isempty(IndexChannel)
                                    if isempty(obj.RawFile)
                                        obj.Handles.Load.Enable = 'on';
                                        obj.Handles.StartPath.Enable = 'on';
                                        obj.Handles.Exit.Enable = 'on';
                                    else
                                        obj.EnableAll;
                                    end
                                    return
                                else
                                    Channel = IndexChannel;
                                end
                            end
                            TempRawValues = RawLoaded(:,Channel);
                            TempRawTimes = RawLoaded(:,1);
                            TempRawFrequency = 1/mean(diff(TempRawTimes));
                        end
                    end
                case '.log'
                    try
                        % Open the file
                        fileID = fopen(TempRawFile, 'r');

                        % Skip header lines until we reach the data section
                        Valid = false;
                        while true
                            currentLine = fgetl(fileID);
                            if contains(currentLine, {'ACQ_TIME_TICS', 'CHANNEL', 'VALUE'})
                                Valid = true;
                                break;
                            end
                        end
                        if ~Valid
                            Wn = warndlg(['The file does not contain a valid ECG signal as [ACQ_TIME_TICS, CHANNEL, VALUE].'...
                                newline 'Aborting.']);
                            waitfor(Wn)
                            obj.EnableAll;
                            return
                        end
                        % Read the data
                        data = textscan(fileID, '%d %s %d %*s', 'Delimiter', ' ', 'MultipleDelimsAsOne', true);
                        % Close the file
                        fclose(fileID);
                        % Create the table
                        dataTable = table(data{:}, 'VariableNames', {'ACQ_TIME_TICS', 'CHANNEL', 'VALUE'});
                        if TempReloadMode
                            Loaded_LogFile = load(TempLogFile);
                            % Legacy
                            if ~isfield(Loaded_LogFile.Parameters,'Current')
                                Channel = Loaded_LogFile.Parameters.Channel;
                            else
                                Channel = Loaded_LogFile.Parameters.Current.Channel;
                            end
                        else

                            Channels_Strings = unique(dataTable.CHANNEL);
                            if numel(Channels_Strings)>1
                                [IndexChannel] = listdlg('PromptString','Select the ECG channel(s) to use:',...
                                    'SelectionMode','multiple',...
                                    'ListString',Channels_Strings);
                                if numel(IndexChannel)>2 || numel(IndexChannel)<1
                                    Wn = warndlg(['Can only select one or two (differential) channels.'...
                                        newline 'Aborting.']);
                                    waitfor(Wn)
                                    obj.EnableAll;
                                    return
                                end
                            else
                                IndexChannel = 1;
                            end
                            if any(isnan(IndexChannel)) || isempty(IndexChannel)
                                if isempty(obj.RawFile)
                                    obj.Handles.Load.Enable = 'on';
                                    obj.Handles.StartPath.Enable = 'on';
                                    obj.Handles.Exit.Enable = 'on';
                                else
                                    obj.EnableAll;
                                end
                                return
                            else
                                Channel = Channels_Strings(IndexChannel);
                            end
                        end

                        for Cn = 1 : numel(Channel)
                            IndxC = strcmpi(dataTable.CHANNEL,Channel{Cn});
                            TempRawValues{Cn} = dataTable.VALUE(IndxC);
                            TempRawTimes{Cn} = (dataTable.ACQ_TIME_TICS(IndxC))';
                            TempRawTimes{Cn} = double(TempRawTimes{Cn} - TempRawTimes{Cn}(1))/1000;
                        end
                        if numel(Channel)>1
                            UnifiedTimes = unique(sort([TempRawTimes{:}]));
                            % Preallocate with NaNs
                            TempRawValues = NaN(numel(UnifiedTimes), numel(Channel));
                            % Align values to the unified timeline
                            for Cn = 1 : numel(Channel)
                                CurrentTimes = TempRawTimes{Cn};
                                CurrentValues = TempRawValues{Cn};
                                [~, LocInUnified] = ismember(CurrentTimes, UnifiedTimes);
                                TempRawValues(LocInUnified(LocInUnified > 0), Cn) = CurrentValues;
                            end

                            TempRawValues = diff(TempRawValues,[],2);
                            TempRawTimes = UnifiedTimes';
                        else
                            TempRawValues = TempRawValues{1};
                            TempRawTimes = (TempRawTimes{1})';
                        end
                       
                        TempRawTimes = TempRawTimes';
                        TempRawFrequency = 1/mean(diff(TempRawTimes));
                        TempRawValues = obj.InterpNaN(TempRawValues,ceil(obj.MaxNaNRange*TempRawFrequency));
                    catch
                        Wn = warndlg(['The file does not contain a valid ECG signal as [ACQ_TIME_TICS, CHANNEL, VALUE].'...
                            newline 'Aborting.']);
                        waitfor(Wn)
                        obj.EnableAll;
                        return
                    end
                case {'.txt','.csv'}
                    try
                        RawLoaded = readtable(TempRawFile);
                        if TempReloadMode
                            Loaded_LogFile = load(TempLogFile);
                            % Legacy
                            if ~isfield(Loaded_LogFile.Parameters,'Current')
                                Channel = Loaded_LogFile.Parameters.Channel;
                            else
                                Channel = Loaded_LogFile.Parameters.Current.Channel;
                            end
                        else
                            VarList = RawLoaded.Properties.VariableNames;
                            Channels_Strings = VarList(contains(VarList,'ECG'));
                            TimeVar_String = [];
                            if any(contains(lower(VarList),'volume'))
                                TimeVar_String = VarList(contains(lower(VarList),'volume'));
                            else
                                TimeVar_String = VarList(contains(lower(VarList),'time'));
                            end
                            Channels_Strings = VarList(contains(lower(VarList),'ecg'));
                            if numel(TimeVar_String)~=1 || ~(numel(Channels_Strings)>=1)
                                Wn = warndlg(['The file does not contain a valid ECG signal as [TimeStamps, Channel1_Values,..., Channeln_Values].'...
                                    newline 'Aborting.']);
                                waitfor(Wn)
                                obj.EnableAll;
                                return
                            end
                            if numel(Channels_Strings)>1
                                [IndexChannel] = listdlg('PromptString','Select the ECG channel(s) to use:',...
                                    'SelectionMode','multiple',...
                                    'ListString',Channels_Strings);
                                if numel(IndexChannel)>2 || numel(IndexChannel)<1
                                    Wn = warndlg(['Can only select one or two (differential) channels.'...
                                        newline 'Aborting.']);
                                    waitfor(Wn)
                                    obj.EnableAll;
                                    return
                                end
                            else
                                IndexChannel = 1;
                            end
                            if any(isnan(IndexChannel)) || isempty(IndexChannel)
                                if isempty(obj.RawFile)
                                    obj.Handles.Load.Enable = 'on';
                                    obj.Handles.StartPath.Enable = 'on';
                                    obj.Handles.Exit.Enable = 'on';
                                else
                                    obj.EnableAll;
                                end
                                return
                            else
                                Channel = Channels_Strings(IndexChannel);
                            end
                        end
                        for Cn = 1 : numel(Channel)
                            TempRawValues_Cn = RawLoaded.(Channel{Cn});
                            % Check types (we cannot know ahead, and we leave
                            % the possibility to have extra columns)
                            if ~isnumeric(TempRawValues_Cn)
                                % Likely cells of strings
                                cellArray = strrep(TempRawValues_Cn, ',', '.');
                                joinedString = strjoin(cellArray, ' ');
                                numericMatrix = sscanf(joinedString, '%f');
                                numRows = length(TempRawValues_Cn);  % Number of rows in the original data
                                TempRawValues_Cn = reshape(numericMatrix, 1, numRows)';
                            end
                            TempRawValues(:,Cn) = TempRawValues_Cn;
                        end
                        if numel(Channel)>1
                            TempRawValues = diff(TempRawValues,[],2);
                        end
                        TempRawTimes = RawLoaded.(TimeVar_String{1});
                        if ~isnumeric(TempRawTimes)
                            % Likely cells of strings
                            cellArray = strrep(TempRawTimes, ',', '.');
                            joinedString = strjoin(cellArray, ' ');
                            numericMatrix = sscanf(joinedString, '%f');
                            numRows = length(TempRawTimes);  % Number of rows in the original data
                            TempRawTimes = reshape(numericMatrix, 1, numRows)';
                        end
                        TempRawTimes = TempRawTimes';
                        [TempRawTimes,IndxU] = unique(TempRawTimes);
                        TempRawValues = TempRawValues(IndxU);
                        TempRawFrequency = 1/mean(diff(TempRawTimes));
                        TempRawValues = obj.InterpNaN(TempRawValues,ceil(obj.MaxNaNRange*TempRawFrequency));
                    catch
                        Wn = warndlg(['The file does not contain a valid ECG signal with one header containing ''time'' and headers containing ''ECGx''.'...
                            newline 'Aborting.']);
                        waitfor(Wn)
                        obj.EnableAll;
                        return
                    end
            end
            if TempReloadMode
                % Get the beats times in memory
                Loaded_HeartbeatsFile = load(TempHeartBeatsFile);
                obj.HeartBeats = round(Loaded_HeartbeatsFile.HeartBeats,6);
                % Legacy/conversion
                if size(obj.HeartBeats,1)>1
                    obj.HeartBeats = obj.HeartBeats';
                end
                
                obj.RemovedWindows = Loaded_HeartbeatsFile.RemovedWindows;
               
                if isfield(Loaded_HeartbeatsFile,'BeatPeaks') && isfield(Loaded_HeartbeatsFile,'GUIver')
                    obj.BeatPeaks = round(Loaded_HeartbeatsFile.BeatPeaks,6);
                else
                    obj.LegacyMode = true;
                    obj.BeatPeaks = [];
                end

                if isfield(Loaded_HeartbeatsFile,'Artefacts') 
                    obj.Artefacts = Loaded_HeartbeatsFile.Artefacts;
                end
                Loaded_LogFile = load(TempLogFile);
                % Reapply parameters
                % Reattribute values one by one in case we change the
                % structure at some point (to prevent any missing property)
                if isfield(Loaded_LogFile.Parameters,'Current')
                    Fields = fieldnames(Loaded_LogFile.Parameters.Current);
                    for F = 1 : numel(Fields)
                        if isfield(obj.Parameters.Current,Fields{F})
                            obj.Parameters.Current.(Fields{F}) = Loaded_LogFile.Parameters.Current.(Fields{F});
                        end
                    end
                else
                    Fields = fieldnames(Loaded_LogFile.Parameters);
                    %Legacy
                    for F = 1 : numel(Fields)
                        if isfield(obj.Parameters,Fields{F})
                            obj.Parameters.Current.(Fields{F}) = Loaded_LogFile.Parameters.(Fields{F});
                        end
                    end
                end

                obj.ApplyParameters;
            else
                obj.RemovedWindows = [];
                obj.Artefacts = [];
            end

            % If we are not reloading, make sure we have the right default
            % parameters 
            if (~strcmpi(obj.Parameters.Current.Species,obj.Species)) && ~TempReloadMode
                obj.RestoreDefault(obj.Parameters.Current.Species);
                obj.Species = obj.Parameters.Current.Species;
            else
                obj.Parameters.Current.Species = obj.Species;
            end

            if  obj.Parameters.Current.BeatPeaksEnable
                obj.Handles.BeatPeaksEnable.Value = 1;
            end

            obj.Path = Path;
            obj.Basename = Basename;
            obj.Ext = Ext;
            obj.Parameters.Current.Channel = Channel;
            obj.Parameters.Current.Frag = Frag;
            obj.ReloadMode = TempReloadMode;
            obj.RawFile = TempRawFile;
            obj.RawFrequency = TempRawFrequency;
            obj.RawTimes = TempRawTimes;
            obj.RawValues = TempRawValues;
            obj.HeartBeatsFile = TempHeartBeatsFile;
            obj.LogFile = TempLogFile;
            obj.AutoLims;
            obj.Preprocess('Force');
            obj.Handles.CurrentFile.String = Basename;
        end


        function EnableAll(obj,varargin)
            if isempty(varargin)
                RefFields = obj.Handles;
            else
                % To restore exactly the same way
                RefFields = obj.Handles.EnablePrint;
            end
            Fields = fields(RefFields);
            Fields = Fields(~contains(Fields,'Zoom')&~contains(Fields,'ZoomSub')&~contains(Fields,'FillRemove')&~contains(Fields,'tool'));
            for F = 1 : numel(Fields)
                if ~isempty(obj.Handles.(Fields{F}))
                    SubFields = fields(RefFields.(Fields{F}));
                    if isprop(RefFields.(Fields{F}),'Enable')
                        obj.Handles.(Fields{F}).Enable = 'on';
                    elseif ~(contains(class(RefFields.(Fields{F})),'graphics'))
                        for SF = 1 : numel(SubFields)
                            if isprop(RefFields.(Fields{F}).(SubFields{SF}),'Enable')
                                obj.Handles.(Fields{F}).(SubFields{SF}).Enable = 'on';
                            end
                        end
                    end
                end
            end
            obj.Figure.KeyPressFcn = {@(Src,Key)obj.KeyPressCB(Src,Key)};
            drawnow
        end

        function obj = DisableAll(obj)
            Fields = fields(obj.Handles);
            Fields = Fields(~contains(Fields,'Zoom')&~contains(Fields,'ZoomSub')&~contains(Fields,'FillRemove'));
            for F = 1 : numel(Fields)
                if ~isempty(obj.Handles.(Fields{F}))
                    SubFields = fields(obj.Handles.(Fields{F}));
                    if isprop(obj.Handles.(Fields{F}),'Enable')
                        if ~contains(Fields{F},'tool')
                            obj.Handles.EnablePrint.(Fields{F}).Enable = obj.Handles.(Fields{F}).Enable;
                        end
                        obj.Handles.(Fields{F}).Enable = 'off';
                    elseif ~(contains(class(obj.Handles.(Fields{F})),'graphics'))
                        for SF = 1 : numel(SubFields)
                            if isprop(obj.Handles.(Fields{F}).(SubFields{SF}),'Enable')
                                if ~contains([Fields{F},SubFields{SF}],'tool')
                                    obj.Handles.EnablePrint.(Fields{F}).(SubFields{SF}).Enable = obj.Handles.(Fields{F}).(SubFields{SF}).Enable;
                                end
                                obj.Handles.(Fields{F}).(SubFields{SF}).Enable = 'off';
                            end
                        end
                    end
                end
            end            
            drawnow
            obj.Figure.KeyPressFcn = [];
        end

        function StartPathCB(obj)
            TempStartPath = uigetdir;
            if TempStartPath~=0
                obj.StartPath = [TempStartPath filesep];
            end
        end

        %% Parameters callbacks
        % Pre-processing
        function DeDriftEnableCB(obj)
            obj.Parameters.Current.DeDriftEnable =  obj.Handles.DeDrift_CheckBox.Value;
            obj.Preprocess;
        end
        
        function InverseECGCB(obj)
            obj.Parameters.Current.InverseECG =  obj.Handles.InverseECG_CheckBox.Value;
            obj.Preprocess;
        end

        function DeDriftKernelEditCB(obj)
            if str2double(obj.Handles.DeDriftKernel.Edit.String)>0
                % If too large, the smooth function will take care of the
                % error
                obj.Parameters.Current.DeDriftKernel = str2double(obj.Handles.DeDriftKernel.Edit.String);
                obj.Preprocess;
            else
                obj.Handles.DeDriftKernel.Edit.String = num2str(obj.Parameters.Current.DeDriftKernel);
            end
        end

        function BPEnableCB(obj)
            obj.Parameters.Current.BPEnable =  obj.Handles.BandPass_CheckBox.Value;
            obj.Preprocess;
        end

        function BPHighEditCB(obj)
            if str2double(obj.Handles.BPHigh.Edit.String)>0 && str2double(obj.Handles.BPHigh.Edit.String)>obj.Parameters.Current.BPLow && str2double(obj.Handles.BPHigh.Edit.String)<obj.RawFrequency/2
                obj.Parameters.Current.BPHigh = str2double(obj.Handles.BPHigh.Edit.String);
            else
                obj.Handles.BPHigh.Edit.String = num2str(obj.Parameters.Current.BPHigh);
            end
        end

        function BPLowEditCB(obj)
            if str2double(obj.Handles.BPLow.Edit.String)>0 && str2double(obj.Handles.BPLow.Edit.String)<obj.Parameters.Current.BPHigh
                obj.Parameters.Current.BPLow = str2double(obj.Handles.BPLow.Edit.String);
            else
                obj.Handles.BPLow.Edit.String = num2str(obj.Parameters.Current.BPLow);
            end
        end

        function BPSetCB(obj)
            obj.BPHighEditCB;
            obj.BPLowEditCB;
            if obj.Parameters.Current.BPEnable
                obj.Preprocess;
            end
        end

        % Detection
        function PowerEditCB(obj)
            if str2double(obj.Handles.Power.Edit.String)>0 && str2double(obj.Handles.Power.Edit.String)<10
                obj.Parameters.Current.Power = str2double(obj.Handles.Power.Edit.String);
                obj.Detect;
            else
                obj.Handles.Power.Edit.String = num2str(obj.Parameters.Current.Power);
            end
        end

        function ThresholdEditCB(obj)
            if str2double(obj.Handles.Threshold.Edit.String)>0
                obj.Parameters.Current.Threshold = str2double(obj.Handles.Threshold.Edit.String);
                obj.Handles.ThresholdLine.YData = [obj.Parameters.Current.Threshold obj.Parameters.Current.Threshold];
            else
                obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Current.Threshold);
            end
        end

        function SmoothDetectionEditCB(obj)
            if str2double(obj.Handles.SmoothDetection.Edit.String)>0
                obj.Parameters.Current.SmoothDetection = str2double(obj.Handles.SmoothDetection.Edit.String);
                obj.Detect;
            else
                obj.Handles.SmoothDetection.Edit.String = num2str(obj.Parameters.Current.SmoothDetection);
            end
        end

        function WaveformWindowLowEditCB(obj)
            if str2double(obj.Handles.WaveformWindowLow.Edit.String)<obj.Parameters.Current.WaveformWindowHigh
                obj.Parameters.Current.WaveformWindowLow = str2double(obj.Handles.WaveformWindowLow.Edit.String);
                obj.Detect;
            else
                obj.Handles.WaveformWindowLow.Edit.String = num2str(obj.Parameters.Current.WaveformWindowLow);
            end
        end

        function WaveformWindowHighEditCB(obj)
            if str2double(obj.Handles.WaveformWindowHigh.Edit.String)>obj.Parameters.Current.WaveformWindowLow
                obj.Parameters.Current.WaveformWindowHigh = str2double(obj.Handles.WaveformWindowHigh.Edit.String);
                obj.Detect;
            else
                obj.Handles.WaveformWindowHigh.Edit.String = num2str(obj.Parameters.Current.WaveformWindowHigh);
            end
        end

        function ThresholdSetCB(obj)
            if str2double(obj.Handles.Threshold.Edit.String)>0
                obj.Parameters.Current.Threshold = str2double(obj.Handles.Threshold.Edit.String);
                obj.Handles.ThresholdLine.YData = [obj.Parameters.Current.Threshold obj.Parameters.Current.Threshold];
                obj.Detect;
            else
                obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Current.Threshold);
            end
        end

        function WindowLHSetCB(obj)
            obj.WaveformWindowLowEditCB;
            obj.WaveformWindowHighEditCB;
            obj.Detect;
        end

        function ThresholdDragCB(obj)
            if ~obj.Dragging
                obj.Figure.WindowButtonMotionFcn = @(~,~)obj.MovingThresholdLine;
                obj.Figure.WindowButtonUpFcn = @(~,~)obj.ThresholdDragCB;
                obj.Dragging = true;
            else
                obj.Dragging = false;
                obj.Figure.WindowButtonMotionFcn = [];
                obj.Figure.WindowButtonUpFcn = [];
            end
        end

        function MovingThresholdLine(obj)
            CurrentCursor = obj.Axes.Elevated.CurrentPoint;
            if CurrentCursor(1,2)>=0 && CurrentCursor(1,2)<=obj.Axes.Elevated.YLim(2)
                obj.Handles.ThresholdLine.YData = [CurrentCursor(1,2) CurrentCursor(1,2)];
                obj.Handles.Threshold.Edit.String = num2str(CurrentCursor(1,2),3);
                drawnow;
            end
        end


        % Manual interventions

        % Removed because hardly used by users
%         function LockXCB(obj) 
%             if obj.Handles.LockX.Value==0
%                 obj.Handles.ZoomElevated.Motion = 'both';
%                 obj.Handles.ZoomSubHR.Motion = 'both';
%                 obj.Handles.ZoomSubPeaks.Motion = 'both';
%                 obj.Handles.ZoomSubRaw.Motion = 'both';
%             elseif obj.Handles.LockX.Value==1
%                 obj.Handles.ZoomElevated.Motion = 'vertical';
%                 obj.Handles.ZoomSubHR.Motion = 'vertical';
%                 obj.Handles.ZoomSubPeaks.Motion = 'vertical';
%                 obj.Handles.ZoomSubRaw.Motion = 'vertical';
%                 obj.Handles.LockY.Value = 0;
%             end
%         end
% 
%         function LockYCB(obj)
%             if obj.Handles.LockY.Value==0
%                 obj.Handles.ZoomElevated.Motion = 'both';
%                 obj.Handles.ZoomSubHR.Motion = 'both';
%                 obj.Handles.ZoomSubPeaks.Motion = 'both';
%                 obj.Handles.ZoomSubRaw.Motion = 'both';
%             elseif obj.Handles.LockY.Value==1
%                 obj.Handles.ZoomElevated.Motion = 'horizontal';
%                 obj.Handles.ZoomSubHR.Motion = 'horizontal';
%                 obj.Handles.ZoomSubPeaks.Motion = 'horizontal';
%                 obj.Handles.ZoomSubRaw.Motion = 'horizontal';
%                 obj.Handles.LockX.Value = 0;
%             end
%         end


        function ExportCSVHeartbeatsCB(obj)
            if obj.Handles.ExportCSVHeartbeats.Value==0
                obj.Parameters.Current.ExportCSVHeartbeats = 0;
            else
                obj.Parameters.Current.ExportCSVHeartbeats = 1;
            end
        end

        function ExportCSVHRCB(obj)
            if obj.Handles.ExportCSVHR==0
                obj.Parameters.Current.ExportCSVHR = 0;
            else
                obj.Parameters.Current.ExportCSVHR = 1;
            end
        end

        function EnableShapesCB(obj)
            if obj.Handles.EnableShapes.Value==0
                obj.Parameters.Current.ShapesEnable = 0;
            else
                obj.Parameters.Current.ShapesEnable = 1;
            end
            obj.PlotBeatShapes;
        end

        function PlotBeatShapes(obj)
            obj.DisableAll;
            delete(obj.Handles.ShapesBeats);
            % Instead of plotting individual waveforms, we'll just
            % overlay full ECG traces again, with NaN ranges
            % (much faster/efficient even when navigating
            % afterwards)
            if obj.Parameters.Current.ShapesEnable
                Indx = obj.Intersect(obj.HeartBeats,obj.Peaks);
                [~,Indx2] = setdiff(obj.Peaks,obj.HeartBeats);
                TempSignal1 = NaN(size(obj.Preprocessed));
                TempSignal2 = NaN(size(obj.Preprocessed));
                FullIndx1 = obj.RangeShapes(Indx,:);
                FullIndx1 = sort(FullIndx1(:));
                FullIndx2 = obj.RangeShapes(Indx2,:);
                FullIndx2 = sort(FullIndx2(:));
                TempSignal1(FullIndx1) = obj.Preprocessed(FullIndx1);
                TempSignal2(FullIndx2) = obj.Preprocessed(FullIndx2);
                obj.Handles.ShapesBeats = [plot(obj.Times, TempSignal2,'Color',[0.8 0.8 0.8],'LineWidth',1.5,'Parent',obj.Axes.SubPeaks);
                    plot(obj.Times, TempSignal1,'Color',obj.Colors(2,:),'LineWidth',1.5,'Parent',obj.Axes.SubPeaks)];
            else
                obj.Handles.ShapesBeats = [];
            end
            obj.EnableAll;
        end

        function BeatPeaksEnableCB(obj)
            if obj.Handles.BeatPeaksEnable.Value==0
                obj.Parameters.Current.BeatPeaksEnable = 0;
            else
                obj.Parameters.Current.BeatPeaksEnable = 1;
            end
                obj.PlotBeatPeaks;
        end

        function PlotBeatPeaks(obj)
            obj.DisableAll;
            delete(obj.Handles.BeatPeaks)
            if obj.Parameters.Current.BeatPeaksEnable  
                Indx = obj.Intersect(obj.HeartBeats,obj.Peaks);
                obj.Handles.BeatPeaks = plot((obj.BeatPeaks(Indx,1))', (obj.BeatPeaks(Indx,2))','o','Color','k','MarkerSize',10,'LineWidth',1.5,'Parent',obj.Axes.SubPeaks);
            else
                obj.Handles.BeatPeaks = [];
            end
            obj.EnableAll;
        end

        function AutoUpdateHRCB(obj)
            if obj.Handles.AutoUpdateHR.Value==0
                obj.Parameters.Current.AutoUpdate = 0;
            else
                obj.Parameters.Current.AutoUpdate = 1;
            end
        end

        function SaveCB(obj)
            obj.DisableAll;
            Indx = obj.Intersect(obj.HeartBeats,obj.Peaks);
            BeatPeaks = obj.BeatPeaks(Indx,1);
            if obj.Frequency<obj.RawFrequency
                % We need to rederive the peaks time with the full sampling
                % rate: re-preprocess the signal, extract peaks the same
                % way, and keep only the validated peaks by using the very
                % same index

                TempPreprocessed = obj.RawValues;
                TempPreprocessed = TempPreprocessed-nanmean(TempPreprocessed);

                % Flipping signal
                if obj.Parameters.Current.InverseECG
                    TempPreprocessed = -TempPreprocessed;
                end

                % Remove drift by using sliding average
                if obj.Parameters.Current.DeDriftEnable
                    TempPreprocessed = TempPreprocessed - smoothdata(TempPreprocessed,'gaussian',obj.Parameters.Current.DeDriftKernel);
                end

                % Bandpass filter
                if obj.Parameters.Current.BPEnable
                   TempPreprocessed = bandpass(TempPreprocessed,[obj.Parameters.Current.BPLow obj.Parameters.Current.BPHigh],obj.Frequency);
                end

                % Notch filter
                if obj.Parameters.Current.NotchFilter
                    TempPreprocessed = bandstop(TempPreprocessed,obj.PowerGrid+[-5 5],obj.Frequency,'ImpulseResponse','iir');
                end

                if obj.Parameters.Current.BeatPeaksFilter
                    TempRawValues = smoothdata(TempPreprocessed,'sgolay');
                else
                    TempRawValues = TempPreprocessed;
                end
                % Convert back into samples
                BeatPeaksIndex_S = round(BeatPeaks*obj.RawFrequency - obj.Parameters.Current.Frag * obj.RawFrequency);
                
                Range = ceil(1+obj.RawFrequency/obj.Frequency);
                BeatPeaksValue = arrayfun(@(x) max(TempRawValues(BeatPeaksIndex_S(x)-Range : BeatPeaksIndex_S(x)+Range)),1:numel(BeatPeaks));
                BeatPeaksIndex = arrayfun(@(x) find(TempRawValues(BeatPeaksIndex_S(x)-Range : BeatPeaksIndex_S(x)+Range)==BeatPeaksValue(x)),1:numel(BeatPeaks),'UniformOutput',false);
                % Check if we have ties...
                IndxMultiple = find(arrayfun(@(x) numel(BeatPeaksIndex{x})>1,1:numel(BeatPeaksIndex)));
                if ~isempty(IndxMultiple)
                    for IM = 1 : numel(IndxMultiple)
                        [~,IndxKeep] = min(abs(BeatPeaksIndex{IndxMultiple(IM)}-Range));
                        Sh = BeatPeaksIndex{IndxMultiple(IM)};
                        BeatPeaksIndex{IndxMultiple(IM)} = Sh(IndxKeep);
                    end
                end
                BeatPeaksIndex = cell2mat(BeatPeaksIndex) - Range - 1;
                BeatPeaksTimes = obj.RawTimes(BeatPeaksIndex_S+BeatPeaksIndex');
            else
                BeatPeaksTimes = BeatPeaks;
            end

            % Make sure we have at least one timestamp per excluded 
            % range to provide a breaking point after processing heart rate
            AddedBeat = [];
            if ~isempty(obj.RemovedWindows)
                for R = 1 : size(obj.RemovedWindows,1)
                    RemoveIndx = BeatPeaksTimes>=obj.RemovedWindows(R,1) & BeatPeaksTimes <= (obj.RemovedWindows(R,2));
                    if ~any(RemoveIndx)
                        AddedBeat = [AddedBeat,mean(obj.RemovedWindows(R,:))];
                    end
                end
            end
            if ~isempty(obj.Artefacts)
                for R = 1 : size(obj.Artefacts,1)
                    RemoveIndx = BeatPeaksTimes>=obj.Artefacts(R,1) & BeatPeaksTimes <= (obj.Artefacts(R,2));
                    if  ~any(RemoveIndx)
                        AddedBeat = [AddedBeat,mean(obj.Artefacts(R,:))];
                    end
                end
            end
            BeatPeaksTimes = sort([BeatPeaksTimes,AddedBeat]);

            % Perpare and save .mat heart beats file
            SavedHeartBeats.BeatPeaks = BeatPeaksTimes;
            SavedHeartBeats.HeartBeats = obj.HeartBeats;
            SavedHeartBeats.Artefacts = obj.Artefacts;
            SavedHeartBeats.RemovedWindows = obj.RemovedWindows;
            SavedHeartBeats.GUIver = obj.CurrVer;
            save(obj.HeartBeatsFile,'-Struct','SavedHeartBeats');

            % Logfile
            CurrLog = {datetime,getenv('username'),obj.CurrVer};
            if exist(obj.LogFile,'file')
                Log = load(obj.LogFile);
                if isfield(Log,'Log')
                    if size(Log.Log,2) ~= 3
                        Log.Log = [Log.Log,cell(size(Log.Log,1),3-size(Log.Log,2))];
                    end
                    Log.Log = [Log.Log; CurrLog];
                else
                    Log.Log = [CurrLog]; % Legacy
                end
            else
                Log.Log = CurrLog;
            end
            Log.Parameters = obj.Parameters;
            Log.Files.RawECG_File = obj.RawFile;
            Log.Files.RawECG_FileType = obj.Ext;
            save(obj.LogFile,'-Struct','Log');

            % Export as .csvs if requested
            if obj.Parameters.Current.ExportCSVHeartbeats
                Data_CSV = BeatPeaksTimes;
                % Set NaN values for the ranges to exclude (not based on
                % window-size), to make sure no false beat goes through
                if ~isempty(obj.RemovedWindows)
                    for R = 1 : size(obj.RemovedWindows,1)
                        RemoveIndx = Data_CSV>=obj.RemovedWindows(R,1) & Data_CSV <= (obj.RemovedWindows(R,2));
                        Data_CSV(RemoveIndx) = NaN;
                    end
                end
                if ~isempty(obj.Artefacts)
                    for R = 1 : size(obj.Artefacts,1)
                        RemoveIndx = Data_CSV>=obj.Artefacts(R,1) & Data_CSV <= (obj.Artefacts(R,2));
                        Data_CSV(RemoveIndx) = NaN;
                    end
                end
                CSV_File = [obj.Path filesep obj.Basename '_HeartBeats.csv'];
                writematrix(Data_CSV',CSV_File)
            end
            if obj.Parameters.Current.ExportCSVHR
                % Process HR with the dedicated function to clean from the
                % artefacts/excluded ranges
                Data_CSV = GetHeartRate(obj.HeartBeatsFile,'WindowSize',obj.Parameters.Current.SlidingWindowSize);
                CSV_File = [obj.Path filesep obj.Basename '_HeartRate.csv'];
                writematrix(Data_CSV,CSV_File)
            end
            obj.EnableAll;
        end

        function ExitCB(obj)
            close(obj.Figure)
        end

        function AutoLims(obj)
            obj.Axes.Elevated.XLimMode = 'auto';
            obj.Axes.SubHR.XLimMode = 'auto';
            obj.Axes.SubPeaks.XLimMode = 'auto';
            obj.Axes.SubRaw.XLimMode = 'auto';
            obj.Axes.Elevated.YLimMode = 'auto';
            obj.Axes.SubHR.YLimMode = 'auto';
            obj.Axes.SubPeaks.YLimMode = 'auto';
            obj.Axes.SubRaw.YLimMode = 'auto';
        end

        function EvaluateWindow(obj)
            drawnow
            if obj.Axes.SubHR.XLim(1)<0
                obj.Axes.SubHR.XLim(1) = 0;
            elseif obj.Axes.SubHR.XLim(2)>obj.Times(end)
                obj.Axes.SubHR.XLim(2) = obj.Times(end);
            end
            drawnow
            if obj.Handles.SliderLine.XData(1)<obj.Axes.SubHR.XLim(1) || obj.Handles.SliderLine.XData(1)>obj.Axes.SubHR.XLim(2)
                obj.Handles.SliderLine.XData = [1 1] * obj.Axes.SubHR.XLim(1) + 0.5*diff(obj.Axes.SubHR.XLim);
            end
        end

        function SliderCB(obj)
            if ~obj.Dragging
                if ~isempty(obj.Times)
                    obj.Dragging = true;
                    obj.Figure.WindowButtonMotionFcn = @(~,~)obj.MovingSlider;
                    obj.Figure.WindowButtonUpFcn = @(~,~)obj.Axes.SliderCB;
                end
            else
                obj.Dragging = false;
                obj.Figure.WindowButtonMotionFcn = [];
                obj.Figure.WindowButtonUpFcn = [];
            end
        end

        function MovingSlider(obj)
            CurrentCursor = obj.Axes.Slider.CurrentPoint;
            if (CurrentCursor(1) + 0.5*diff(obj.Axes.SubHR.XLim))<=obj.Times(end) && (CurrentCursor(1) - 0.5*diff(obj.Axes.SubHR.XLim))>=obj.Times(1)
                obj.Axes.SubHR.XLim = [CurrentCursor(1)-0.5*diff(obj.Axes.SubHR.XLim) CurrentCursor(1)+0.5*diff(obj.Axes.SubHR.XLim)];
                obj.Handles.SliderLine.XData = [CurrentCursor(1) CurrentCursor(1)];
            elseif (CurrentCursor(1) + 0.5*diff(obj.Axes.SubHR.XLim))>obj.Times(end)
                obj.Axes.SubHR.XLim = [obj.Times(end)-diff(obj.Axes.SubHR.XLim) obj.Times(end)];
                if CurrentCursor(1) > obj.Times(end)
                    obj.Handles.SliderLine.XData = [obj.Times(end) obj.Times(end)];
                else
                    obj.Handles.SliderLine.XData = [CurrentCursor(1) CurrentCursor(1)];
                end
            else
                obj.Axes.SubHR.XLim = [obj.Times(1) obj.Times(1)+diff(obj.Axes.SubHR.XLim)];
                if CurrentCursor(1) < obj.Times(1)
                    obj.Handles.SliderLine.XData = [obj.Times(1) obj.Times(1)];
                else
                    obj.Handles.SliderLine.XData = [CurrentCursor(1) CurrentCursor(1)];
                end
            end
            drawnow
        end

        function SelectBeat(obj)
            % Retrieve X coordinate
            Clicked = obj.Axes.SubPeaks.CurrentPoint;
            % Find closer peak
            [~,IndexPoint] = min(abs(Clicked(1) - obj.Peaks));
            ClickedPeak = obj.Peaks(IndexPoint);
            % Check if selected or not
            Comm = obj.Intersect(ClickedPeak,obj.HeartBeats);
            if any(Comm)
                IndxD = Comm;
                obj.Handles.MarkersBeats.XData(IndxD) = [];
                obj.Handles.MarkersBeats.YData(IndxD) = [];
                obj.HeartBeats(IndxD) = [];
                if obj.Parameters.Current.ShapesEnable
                    obj.PlotBeatShapes;
                end
                if obj.Parameters.Current.BeatPeaksEnable
                    obj.PlotBeatPeaks;
                end
                if obj.Parameters.Current.AutoUpdate
                    obj.DisableAll;
                    obj.ProcessHeartRate;
                end
            else
                obj.HeartBeats = sort([obj.HeartBeats,ClickedPeak]);
                obj.Handles.MarkersBeats.XData = sort([obj.Handles.MarkersBeats.XData,ClickedPeak]);
                obj.Handles.MarkersBeats.YData = [obj.Handles.MarkersBeats.YData,0];
                if obj.Parameters.Current.ShapesEnable
                    obj.PlotBeatShapes;
                end
                if obj.Parameters.Current.BeatPeaksEnable
                    obj.PlotBeatPeaks;
                end
                if obj.Parameters.Current.AutoUpdate
                    obj.DisableAll;
                    obj.ProcessHeartRate;
                end
            end
        end

        function AddRangeCB(obj)
            D = drawrectangle(obj.Axes.SubPeaks);
            NewWindow = [D.Position(1),D.Position(1)+D.Position(3)];
            delete(D)
            obj.RemovedWindows = sortrows([obj.RemovedWindows; NewWindow],1);
            TempRemovedWindows = obj.RemovedWindows;

            % Find and remove potential overlaps
            for RR = 2 : size(TempRemovedWindows,1)
                if (TempRemovedWindows(RR,1)<TempRemovedWindows(RR-1,2))
                    TempRemovedWindows(RR,1) = TempRemovedWindows(RR-1,1);
                    TempRemovedWindows(RR-1,1) = NaN;
                end
                if (TempRemovedWindows(RR,2)<TempRemovedWindows(RR-1,2))
                    TempRemovedWindows(RR,2) = TempRemovedWindows(RR-1,2);
                    TempRemovedWindows(RR-1,2) = NaN;
                end
            end

            % Trim if overlapping with artefact windows
            if ~isempty(obj.Artefacts)
                for RR = 1 : size(obj.Artefacts,1)
                    IndxO = TempRemovedWindows(:,1) > obj.Artefacts(RR,1) & TempRemovedWindows(:,2) < obj.Artefacts(RR,2);
                    if any(IndxO,2)
                        IndxO = find(IndxO);
                        TempRemovedWindows(IndxO,:) = NaN(numel(IndxO),2);
                    end
                    IndxO = TempRemovedWindows(:,1) < obj.Artefacts(RR,1) & TempRemovedWindows(:,2) > obj.Artefacts(RR,2);
                    if any(IndxO,2)
                        IndxO = find(IndxO);
                        for IL = 1 : numel(IndxO)
                            TempRemovedWindows = [TempRemovedWindows;
                                TempRemovedWindows(IndxO,1) obj.Artefacts(RR,1);
                                obj.Artefacts(RR,2) TempRemovedWindows(IndxO,2) ];
                            TempRemovedWindows(IndxO,:) = NaN(1,2);
                        end
                    end
                    IndxO = TempRemovedWindows(:,2) > obj.Artefacts(RR,1) & TempRemovedWindows(:,2) < obj.Artefacts(RR,2);
                    if any(IndxO,2)
                        IndxO = find(IndxO);
                        for IL = 1 : numel(IndxO)
                            TempRemovedWindows(IndxO,2) = obj.Artefacts(RR,1);
                        end
                    end
                    IndxO = TempRemovedWindows(:,1) > obj.Artefacts(RR,1) & TempRemovedWindows(:,1) < obj.Artefacts(RR,2);
                    if any(IndxO,2)
                        IndxO = find(IndxO);
                        for IL = 1 : numel(IndxO)
                            TempRemovedWindows(IndxO,1) = obj.Artefacts(RR,2);
                        end
                    end
                end
            end
            obj.RemovedWindows = TempRemovedWindows(~any(isnan(TempRemovedWindows),2),:);

            Subs = {'SubPeaks','SubHR','Elevated'};
            for S = 1 : numel(Subs)
                delete(obj.Handles.FillRemovedWindows.(Subs{S}))
                obj.Handles.FillRemovedWindows.(Subs{S}) = arrayfun(@(x) fill([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)], [ obj.Handles.Min.(Subs{S})  obj.Handles.Min.(Subs{S})  obj.Handles.Max.(Subs{S})  obj.Handles.Max.(Subs{S})],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.Axes.(Subs{S}),'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:size(obj.RemovedWindows,1));
                uistack(obj.Handles.FillRemovedWindows.(Subs{S}),'bottom')
                delete(obj.Handles.FillWindowRemoved.(Subs{S}))
                obj.Handles.FillWindowRemoved.(Subs{S}) = arrayfun(@(x) fill([0 obj.Parameters.Current.SlidingWindowSize obj.Parameters.Current.SlidingWindowSize 0]+obj.RemovedWindows(x,2), [ obj.Handles.Min.(Subs{S})  obj.Handles.Min.(Subs{S})  obj.Handles.Max.(Subs{S})  obj.Handles.Max.(Subs{S})],[0.85 0.85 0.9],'EdgeColor',[0.85 0.85 0.9],'FaceColor','none','LineStyle',':','LineWidth',2,'Parent',obj.Axes.(Subs{S})),1:size(obj.RemovedWindows,1));
                uistack( obj.Handles.FillWindowRemoved.(Subs{S}),'bottom')
            end
            if obj.Parameters.Current.AutoUpdate
                obj.DisableAll;
                obj.ProcessHeartRate;
            end
        end

        function SelectWindow(obj,src,~)
            Subs = {'SubPeaks','SubHR','Elevated'};
            if obj.Selected == str2double(src.Tag)
                obj.Selected = [];
                Colors = repmat({[0.85 0.85 0.9]},size(obj.RemovedWindows,1),1);
                LineColors = repmat({[1 1 1]},size(obj.RemovedWindows,1),1);
                for S = 1 : numel(Subs)
                    set(obj.Handles.FillRemovedWindows.(Subs{S}),{'FaceColor'},Colors)
                    set(obj.Handles.FillRemovedWindows.(Subs{S}),{'EdgeColor'},LineColors)
                end
            else
                obj.Selected = str2double(src.Tag);
                Colors = repmat({[0.85 0.85 0.9]},size(obj.RemovedWindows,1),1);
                LineColors = repmat({[1 1 1]},size(obj.RemovedWindows,1),1);
                Colors(obj.Selected,:) = {[0.5 0.85 0.94]};
                LineColors(obj.Selected,:) = {[0 0 0]};
                for S = 1 : numel(Subs)
                    set(obj.Handles.FillRemovedWindows.(Subs{S}),{'FaceColor'},Colors)
                    set(obj.Handles.FillRemovedWindows.(Subs{S}),{'EdgeColor'},LineColors)
                end
            end
        end


        function DeleteRangeCB(obj)
            Subs = {'SubPeaks','SubHR','Elevated'};
            if ~isempty(obj.Selected)
                obj.RemovedWindows(obj.Selected,:) = [];
                for S = 1 : numel(Subs)
                    delete(obj.Handles.FillRemovedWindows.(Subs{S}))
                    obj.Handles.FillRemovedWindows.(Subs{S}) = arrayfun(@(x) fill([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)], [ obj.Handles.Min.(Subs{S})  obj.Handles.Min.(Subs{S})  obj.Handles.Max.(Subs{S})  obj.Handles.Max.(Subs{S})],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.Axes.(Subs{S}),'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:size(obj.RemovedWindows,1));
                    uistack(obj.Handles.FillRemovedWindows.(Subs{S}),'bottom')
                    delete(obj.Handles.FillWindowRemoved.(Subs{S}))
                    obj.Handles.FillWindowRemoved.(Subs{S}) = arrayfun(@(x) fill([0 obj.Parameters.Current.SlidingWindowSize obj.Parameters.Current.SlidingWindowSize 0]+obj.RemovedWindows(x,2), [ obj.Handles.Min.(Subs{S})  obj.Handles.Min.(Subs{S})  obj.Handles.Max.(Subs{S})  obj.Handles.Max.(Subs{S})],[0.75 0.75 0.75],'EdgeColor',[0.75 0.75 0.75],'FaceColor','none','LineStyle','--','LineWidth',1,'Parent',obj.Axes.(Subs{S})),1:size(obj.RemovedWindows,1));
                    uistack( obj.Handles.FillWindowRemoved.(Subs{S}),'bottom')
                end
                if obj.Parameters.Current.AutoUpdate
                    obj.DisableAll;
                    obj.ProcessHeartRate;
                end
            end
            obj.Selected = [];
        end


        
        function PassesNumberCB(obj)
            if str2double(obj.Handles.PassesNumber.Edit.String)>0
                obj.Parameters.Current.PassNumber = str2double(obj.Handles.SlidingWindowSize.Edit.String);
            else
                obj.Handles.PassesNumber.Edit.String = num2str(obj.Parameters.Current.PassNumber);
            end
        end


        % Heart rate
        function SlidingWindowSizeEditCB(obj)
            if str2double(obj.Handles.SlidingWindowSize.Edit.String)>0
                obj.Parameters.Current.SlidingWindowSize = str2double(obj.Handles.SlidingWindowSize.Edit.String);
                obj.ProcessHeartRate;
                obj.Axes.SubHR.YLimMode = 'auto';
            else
                obj.Handles.SlidingWindowSize.Edit.String = num2str(obj.Parameters.Current.SlidingWindowSize);
            end
        end

        function BPMCB(obj)
            if  obj.Handles.BPM.Value ==1
                obj.Parameters.Current.Unit = 'bpm';
                obj.Handles.Hz.Value = 0;
                drawnow
                obj.DisableAll;
                obj.Axes.SubHR.YLabel.String = 'Heart rate (bpm)';
                obj.Axes.SubHR.Children(1).YData = obj.Axes.SubHR.Children(1).YData*60;
            else
                obj.Handles.Hz.Value = 1;
                drawnow
                obj.DisableAll;
                obj.Parameters.Current.Unit = 'Hz';
                obj.Axes.SubHR.YLabel.String = 'Heart rate (Hz)';
                obj.Axes.SubHR.Children(1).YData = obj.Axes.SubHR.Children(1).YData/60;
            end
            obj.Axes.SubHR.YLimMode = 'auto';
            drawnow
            obj.EnableAll;
        end

        function HzCB(obj)
            obj.DisableAll;
            if  obj.Handles.Hz.Value ==1
                obj.Handles.BPM.Value = 0;drawnow
                obj.DisableAll;
                obj.Parameters.Current.Unit = 'Hz';
                obj.Axes.SubHR.YLabel.String = 'Heart rate (Hz)';
                obj.Axes.SubHR.Children(1).YData = obj.Axes.SubHR.Children(1).YData/60;
            else
                obj.Handles.BPM.Value = 1;drawnow
                obj.DisableAll;
                obj.Parameters.Current.Unit = 'bpm';
                obj.Axes.SubHR.YLabel.String = 'Heart rate (bpm)';
                obj.Axes.SubHR.Children(1).YData = obj.Axes.SubHR.Children(1).YData*60;
            end
            drawnow
            obj.EnableAll;
        end

        % Processing functions
        function Preprocess(obj,varargin)
            if ~isempty(obj.Previous)
                Reprocess = false;
                % Check whether anything is different from last call
                % File
                if strcmpi(obj.Previous.File,obj.RawFile)
                    % Bandpass
                    if obj.Parameters.Current.BPEnable ~= obj.Previous.BPEnable
                        Reprocess = true;
                    end
                    if obj.Parameters.Current.BPEnable
                        if obj.Parameters.Current.BPHigh ~= obj.Previous.BPHigh
                            Reprocess = true;
                        end
                        if obj.Parameters.Current.BPLow ~= obj.Previous.BPLow
                            Reprocess = true;
                        end
                    end
                    % Dedrift
                    if obj.Parameters.Current.DeDriftEnable ~= obj.Previous.DeDriftEnable
                        Reprocess = true;
                    end
                    if obj.Parameters.Current.DeDriftKernel ~= obj.Previous.DeDriftKernel
                        Reprocess = true;
                    end
                    % Inverse ECG
                    if obj.Parameters.Current.InverseECG ~= obj.Previous.InverseECG
                        Reprocess = true;
                    end
                else
                    Reprocess = true;
                end
            else
                Reprocess = true;
            end
            if Reprocess || ~isempty(varargin)
                % Make sure interactions are disabled during processing
                obj.DisableAll;
                % Decrease sampling rate if above desired/sufficient value
                % This is applied to the signal only for the processing
                % step, to speed things up. The final beats times will be
                % rederived from the original signal
                if  obj.RawFrequency>obj.Parameters.Current.ProcessingSamplingRate
                    RatesFactor = ceil(obj.RawFrequency/obj.Parameters.Current.ProcessingSamplingRate);
                    obj.Frequency =  obj.RawFrequency/RatesFactor;
                    % Low-pass filtering and decimation
                    ECG_Raw = decimate(obj.RawValues,RatesFactor);
                    IndxStart = mod(numel(obj.RawValues)-1,RatesFactor)+1;
                    obj.Times = obj.RawTimes(IndxStart:RatesFactor:end);
                else
                    obj.Times = obj.RawTimes;
                    ECG_Raw = obj.RawValues;
                    obj.Frequency = obj.RawFrequency;
                end
                obj.Times = round(obj.Times,6);
                obj.Preprocessed = ECG_Raw-nanmean(ECG_Raw);

                % Flipping signal
                if obj.Parameters.Current.InverseECG
                    obj.Preprocessed = -obj.Preprocessed;
                end

                % Remove drift by using sliding average
                if obj.Parameters.Current.DeDriftEnable
                    obj.Preprocessed = obj.Preprocessed - smoothdata(obj.Preprocessed,'gaussian',obj.Parameters.Current.DeDriftKernel);
                end

                % Bandpass filter
                if obj.Parameters.Current.BPEnable
                    obj.Preprocessed = bandpass(obj.Preprocessed,[obj.Parameters.Current.BPLow obj.Parameters.Current.BPHigh],obj.Frequency);
                end

                % Notch filter
                if obj.Parameters.Current.NotchFilter
                    obj.Preprocessed = bandstop(obj.Preprocessed,obj.PowerGrid+[-5 5],obj.Frequency,'ImpulseResponse','iir');
                end

                % Artefacts detection and removal
                Art = [];
                if obj.Parameters.Current.AutoArtefactsRemoval
                    % Elevate
                    SqECG = smoothdata(abs(obj.Preprocessed).^obj.Parameters.Current.Power,'gaussian',obj.Parameters.Current.ArtefactsDetectSmoothing);
                    SqECG2 = SqECG.^2;

                    % Get peaks (automatic detection)
                    [~,~,~,Height] = findpeaks(SqECG2,'MinPeakProminence',median(SqECG2));

                    % Automatically exclude ranges with artifacts
                    RawPeakValueHigh = 100*prctile(Height,92);
                    OutIndex = find(SqECG2>RawPeakValueHigh);
                    TempRaw = ECG_Raw;
                    if numel(OutIndex)>2
                        Art = obj.GetContinuousRanges(OutIndex);
                        % Merge events when close
                        for KOA = 2 : numel(Art(:,1))
                            if (OutIndex(Art(KOA,1))-OutIndex(Art(KOA-1,2)))<(obj.Frequency*0.2) % 200ms
                                Art(KOA,1) = Art(KOA-1,1);
                                Art(KOA-1,:) = NaN(1,3);
                            end
                        end
                        Art = OutIndex(Art(~isnan(Art(:,1)),[1 2]));
                        if numel(Art) == 2
                            Art = Art';
                        end
                        % Expand the ranges
                        Art = Art + round(obj.Frequency*[-0.05 0.05]);
                        Art(Art<1) = 1;
                        Art(Art>numel(obj.Preprocessed)) = numel(obj.Preprocessed);
                        for K = 1 : size(Art,1)
                            obj.Preprocessed(Art(K,1):Art(K,2)) = NaN;
                            TempRaw(Art(K,1):Art(K,2)) = NaN;
                        end
                        obj.IndxRmv = Art;
                    end
                end

                % Plot
                delete(obj.Axes.SubRaw.Children(:))
                plot(obj.Times,ECG_Raw,'LineWidth',1,'Parent',obj.Axes.SubRaw,'Color',obj.Colors(1,:));
                hold(obj.Axes.SubRaw,'on')
                plot(obj.Times,obj.Preprocessed,'LineWidth',1,'Parent',obj.Axes.SubRaw,'Color',obj.Colors(2,:));
                obj.Artefacts = obj.Times(Art);
                drawnow
                if ~isempty(Art)
                    Max = max([obj.Preprocessed;ECG_Raw]);
                    Min = min([obj.Preprocessed;ECG_Raw]);
                    % Plot ranges discarded because of artefacts
                    obj.Handles.FillArtefact.SubRaw = arrayfun(@(x) fill(obj.Times([Art(x,1) Art(x,2) Art(x,2) Art(x,1)]), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor','none','Parent',obj.Axes.SubRaw),1:size(Art,1));
                    uistack(obj.Handles.FillArtefact.SubRaw,'bottom')
                end

                % Set YLim (without artifacts, if any)
                Max = max([obj.Preprocessed;TempRaw]);
                Min = min([obj.Preprocessed;TempRaw]);
                obj.Handles.Min.SubRaw = Min;
                obj.Handles.Max.SubRaw = Max;
                obj.Axes.SubRaw.YLim = [Min - 0.05*(Max-Min) Max + 0.05*(Max-Min)];

                % Adjust axes limits
                obj.SubplotVisual;
                XL = obj.Times([1 end]);
                obj.Axes.Slider.XLimMode = 'manual';
                set([obj.Axes.Elevated,obj.Axes.SubHR obj.Axes.SubPeaks obj.Axes.SubRaw obj.Axes.Slider],'XLim',XL);
                obj.Detect('Pre');
            else
                obj.Detect;
            end
        end

        function Detect(obj,varargin)
            if ~isempty(varargin)
                Reprocess = true;
            else
                if ~isempty(obj.Previous)
                    Reprocess = false;
                    % Check whether anything is different from last call
                    % File
                    if strcmpi(obj.Previous.File,obj.RawFile)
                        % Power
                        if ~(obj.Parameters.Current.Power == obj.Previous.Power)
                            Reprocess = true;
                        end
                        % Threshold
                        if ~(obj.Parameters.Current.Threshold == obj.Previous.Threshold)
                            Reprocess = true;
                        end
                        % SmoothDetection
                        if ~(obj.Parameters.Current.SmoothDetection == obj.Previous.SmoothDetection)
                            Reprocess = true;
                        end
                        % WaveformWindowLow
                        if ~(obj.Parameters.Current.WaveformWindowLow == obj.Previous.WaveformWindowLow)
                            Reprocess = true;
                        end
                        % WaveformWindowHigh
                        if ~(obj.Parameters.Current.WaveformWindowHigh == obj.Previous.WaveformWindowHigh)
                            Reprocess = true;
                        end
                    end
                else
                    Reprocess = true;
                end
            end
            if Reprocess
                % Make sure interactions are disabled during processing
                obj.DisableAll;


                if obj.ReloadMode && obj.LegacyMode
                    % Legacy
                    % Some old extractions have different
                    % precision/timestamps, leading to mismatch between
                    % loaded heart beats and detected "overall" peaks:
                    % We need to fetch the corresponding index and merge,
                    % as well as "fix" the heartbeats themselves
                    LegacyPeaks = knnsearch(obj.Times',obj.HeartBeats');
                    obj.HeartBeats = obj.Times(LegacyPeaks);
                else
                    LegacyPeaks = [];
                end

                % Transform values to get the beats more separate from the noise
                SqECG = smoothdata(abs(obj.Preprocessed).^obj.Parameters.Current.Power,'gaussian',4*obj.Parameters.Current.SmoothDetection);
                SqECG2 = SqECG.^2;

                % Get peaks (automatic detection)
                [~,Index,~,Height] = findpeaks(SqECG2);
                PeaksIndex = unique([Index(Height>obj.Parameters.Current.Threshold);LegacyPeaks]);
                SamplesRange = obj.Parameters.Current.WaveformWindowLow:obj.Parameters.Current.WaveformWindowHigh;
                Index_Perc = Height>prctile(Height,70) & Height<prctile(Height,90);
                IndexTemplates = Index(Index_Perc);
                IndexTemplates = IndexTemplates(IndexTemplates>(abs(obj.Parameters.Current.WaveformWindowLow) + 1) & IndexTemplates<(Index(end)-(obj.Parameters.Current.WaveformWindowHigh+1)));
                RangeTemplates = repmat(IndexTemplates,1,numel(SamplesRange)) + SamplesRange;
                PeaksIndex(PeaksIndex<=abs(obj.Parameters.Current.WaveformWindowLow) | PeaksIndex>=(numel(obj.Preprocessed)-obj.Parameters.Current.WaveformWindowHigh)) = [];

                TempShapes = obj.Preprocessed(RangeTemplates);
                obj.Template = nanmedian(zscore(TempShapes,1,2),1);
                HeightOr = Height;
                if isempty(PeaksIndex)
                    Answer = questdlg(['The threshold is too high to extract peaks. Do you wish to put it back into range?' newline '(It will still need adjustments)'],'Please choose...','Yes','No','Yes');
                    waitfor(Answer)
                    if strcmpi(Answer,'Yes')
                        % Adjust value
                        obj.Parameters.Current.Threshold = prctile(HeightOr,0.2);
                        obj.Handles.Threshold.Edit.String = num2str(obj.Parameters.Current.Threshold,3);
                        [~,Index,~,Height] = findpeaks(SqECG2);
                        PeaksIndex = unique([Index(Height>obj.Parameters.Current.Threshold),LegacyPeaks]);
                        SamplesRange = obj.Parameters.Current.WaveformWindowLow:obj.Parameters.Current.WaveformWindowHigh;
                        Index_Perc = Height>prctile(Height,70) & Height<prctile(Height,90);
                        IndexTemplates = Index(Index_Perc);
                        IndexTemplates = IndexTemplates(IndexTemplates>(abs(obj.Parameters.Current.WaveformWindowLow) + 1) & IndexTemplates<(Index(end)-(obj.Parameters.Current.WaveformWindowHigh+1)));
                        RangeTemplates = repmat(IndexTemplates,1,numel(SamplesRange)) + SamplesRange;
                        TempShapes = obj.Preprocessed(RangeTemplates);
                        obj.Template = nanmedian(zscore(TempShapes,1,2),1);                
                        PeaksIndex(PeaksIndex<=abs(obj.Parameters.Current.WaveformWindowLow) | PeaksIndex>=(numel(obj.Preprocessed)-obj.Parameters.Current.WaveformWindowHigh)) = [];
                    else
                        obj.EnableAll;
                        return
                    end
                end
               

                % Extract the waveforms
                obj.RangeShapes = repmat(PeaksIndex,1,numel(SamplesRange)) + SamplesRange;
                obj.Shapes = obj.Preprocessed(obj.RangeShapes);
                if isscalar(PeaksIndex)
                    obj.RangeShapes = obj.RangeShapes';
                    obj.Shapes =  obj.Shapes';
                end
                obj.Peaks = round(obj.Times(PeaksIndex),6);
                XcorrAll = (arrayfun(@(x) nanmax(xcorr(obj.Template,zscore(obj.Shapes(x,:),1,2))),1:numel(obj.Shapes(:,1))));
                obj.MaxCorr = nanmax(XcorrAll);

                % Get RPeak position in template
                [~,RPeak_Template] = nanmax(obj.Template);
                while RPeak_Template<=obj.Parameters.Current.PeakRange
                    obj.Parameters.Current.PeakRange = obj.Parameters.Current.PeakRange-1;
                end

                % Get positions for each peak
                % (look for the maximum around estimated location)
                if RPeak_Template+obj.Parameters.Current.PeakRange>size(obj.Shapes,2)
                    CPRe = size(obj.Shapes,2);
                else
                    CPRe = RPeak_Template+obj.Parameters.Current.PeakRange;
                end
                if RPeak_Template-obj.Parameters.Current.PeakRange<1
                    CPRs = 1;
                else
                    CPRs = RPeak_Template-obj.Parameters.Current.PeakRange;
                end
                BeatPeaksValue = arrayfun(@(x) nanmax(obj.Shapes(x,CPRs:CPRe)),1:size(obj.Shapes,1));                
                % If the threshold is low we can pick a range with NaN in
                % the peak range
                NaNIndx = isnan(BeatPeaksValue);
                if any(NaNIndx)
                    BeatPeaksValue(NaNIndx) = [];
                    PeaksIndex(NaNIndx) = [];
                    obj.RangeShapes(NaNIndx,:) = [];
                    obj.Shapes(NaNIndx,:) = [];
                    obj.Peaks(NaNIndx) = [];
                end
                BeatPeaksIndex = arrayfun(@(x) find(obj.Shapes(x,CPRs:CPRe)==BeatPeaksValue(x)),1:size(obj.Shapes,1),'UniformOutput',false);
                % Check if we have ties...
                IndxMultiple = find(arrayfun(@(x) numel(BeatPeaksIndex{x})>1,1:numel(BeatPeaksIndex)));
                if ~isempty(IndxMultiple)
                    for IM = 1 : numel(IndxMultiple)
                        [~,IndxKeep] = nanmin(abs(BeatPeaksIndex{IndxMultiple(IM)}-RPeak_Template));
                        BeatPeaksIndex{IndxMultiple(IM)} = IndxKeep;
                    end
                end
                BeatPeaksIndex = cell2mat(BeatPeaksIndex)+ obj.Parameters.Current.WaveformWindowLow + RPeak_Template - obj.Parameters.Current.PeakRange - 2;
                BeatPeaksTimes = obj.Times(PeaksIndex+BeatPeaksIndex');
                obj.BeatPeaks = [BeatPeaksTimes',BeatPeaksValue'];
                
                % If we are loading a previous file...
                if ~obj.ReloadMode
                    obj.HeartBeats = round(obj.Peaks,6); % For initialization
                end

                delete(obj.Axes.Elevated.Children)
                plot(obj.Times,SqECG2,'LineWidth',1,'Parent',obj.Axes.Elevated,'Color',obj.Colors(2,:));
                hold(obj.Axes.Elevated,'on')
                MaxT = max(SqECG2);
                MinT = min(SqECG2);
                Min = MinT - 0.05*(MaxT-MinT);
                Max = MaxT + 0.05*(MaxT-MinT);
                obj.Handles.Min.Elevated = Min;
                obj.Handles.Max.Elevated = Max;

                TempAxes = {'Elevated', 'SubPeaks', 'SubHR'};
                Windows = {'FillRemovedWindows', 'FillWindowRemoved', 'FillArtefact', 'FillWindowArtefact'};

                for i = 1:length(Windows)
                    for j = 1:length(TempAxes)
                        obj.Handles.(Windows{i}).(TempAxes{j}) = [];
                    end
                end

                if ~isempty(obj.Artefacts)
                    % Plot ranges discarded because of artefacts
                    obj.Handles.FillArtefact.Elevated = arrayfun(@(x) fill(([obj.Artefacts(x,1) obj.Artefacts(x,2) obj.Artefacts(x,2) obj.Artefacts(x,1)]), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor','none','Parent',obj.Axes.Elevated),1:numel(obj.Artefacts(:,1)));
                    uistack(obj.Handles.FillArtefact.Elevated,'bottom')
                    obj.Handles.FillWindowArtefact.Elevated = arrayfun(@(x) fill([0 obj.Parameters.Current.SlidingWindowSize obj.Parameters.Current.SlidingWindowSize 0]+obj.Artefacts(x,2), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor',[0.75 0.75 0.75],'FaceColor','none','LineStyle','--','LineWidth',1,'Parent',obj.Axes.Elevated),1:size(obj.Artefacts,1));
                    uistack(obj.Handles.FillWindowArtefact.Elevated,'bottom')
                end
                if ~isempty(obj.RemovedWindows)
                    % Plot ranges discarded because of artefacts
                    obj.Handles.FillRemovedWindows.Elevated = arrayfun(@(x) fill(([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)]), [Min Min Max Max],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.Axes.Elevated,'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:size(obj.RemovedWindows,1));
                    uistack(obj.Handles.FillRemovedWindows.Elevated,'bottom')
                    obj.Handles.FillWindowRemoved.Elevated = arrayfun(@(x) fill([0 obj.Parameters.Current.SlidingWindowSize obj.Parameters.Current.SlidingWindowSize 0]+obj.RemovedWindows(x,2), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor',[0.75 0.75 0.75],'FaceColor','none','LineStyle','--','LineWidth',1,'Parent',obj.Axes.Elevated),1:size(obj.RemovedWindows,1));
                    uistack( obj.Handles.FillWindowRemoved.Elevated,'bottom')
                end

                obj.Handles.ThresholdLine = plot(obj.Times([1 end]),[obj.Parameters.Current.Threshold obj.Parameters.Current.Threshold],'LineWidth',3,'Parent',obj.Axes.Elevated,'ButtonDownFcn',@(~,~)obj.ThresholdDragCB,'Color',obj.Colors(1,:));
                delete(obj.Axes.SubPeaks.Children)
                plot(obj.Times,obj.Preprocessed,'k','LineWidth',1,'Parent',obj.Axes.SubPeaks);
                hold(obj.Axes.SubPeaks,'on')
                MaxT = max(obj.Preprocessed);
                MinT = min(obj.Preprocessed);
                Min = MinT - 0.05*(MaxT-MinT);
                Max = MaxT + 0.05*(MaxT-MinT);
                obj.Handles.Min.SubPeaks = Min;
                obj.Handles.Max.SubPeaks = Max;

                if obj.Parameters.Current.ShapesEnable
                   obj.PlotBeatShapes;
                else
                    obj.Handles.ShapesBeats = [];
                end

                if obj.Parameters.Current.BeatPeaksEnable
                    obj.PlotBeatPeaks;
                else
                    obj.Handles.BeatPeaks = [];
                end

                if ~isempty(obj.Artefacts)
                    % Plot ranges discarded because of artefacts
                    obj.Handles.FillArtefact.SubPeaks = arrayfun(@(x) fill(([obj.Artefacts(x,1) obj.Artefacts(x,2) obj.Artefacts(x,2) obj.Artefacts(x,1)]), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor','none','Parent',obj.Axes.SubPeaks),1:numel(obj.Artefacts(:,1)));
                    uistack(obj.Handles.FillArtefact.SubPeaks,'bottom')
                    obj.Handles.FillWindowArtefact.SubPeaks = arrayfun(@(x) fill([0 obj.Parameters.Current.SlidingWindowSize obj.Parameters.Current.SlidingWindowSize 0]+obj.Artefacts(x,2), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor',[0.75 0.75 0.75],'FaceColor','none','LineStyle','--','LineWidth',1,'Parent',obj.Axes.SubPeaks),1:size(obj.Artefacts,1));
                    uistack(obj.Handles.FillWindowArtefact.SubPeaks,'bottom')
                end
                if ~isempty(obj.RemovedWindows)
                    % Plot ranges discarded because of artefacts
                    obj.Handles.FillRemovedWindows.SubPeaks = arrayfun(@(x) fill(([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)]), [Min Min Max Max],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.Axes.SubPeaks,'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:size(obj.RemovedWindows,1));
                    uistack(obj.Handles.FillRemovedWindows.SubPeaks,'bottom')
                    obj.Handles.FillWindowRemoved.SubPeaks = arrayfun(@(x) fill([0 obj.Parameters.Current.SlidingWindowSize obj.Parameters.Current.SlidingWindowSize 0]+obj.RemovedWindows(x,2), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor',[0.75 0.75 0.75],'FaceColor','none','LineStyle','--','LineWidth',1,'Parent',obj.Axes.SubPeaks),1:size(obj.RemovedWindows,1));
                    uistack( obj.Handles.FillWindowRemoved.SubPeaks,'bottom')
                end

                obj.Handles.MarkersAll = plot(obj.Peaks,zeros(size(obj.Peaks)),'d','Color',[0.6 0.6 0.6],'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.Axes.SubPeaks,'MarkerSize',12,'MarkerFaceColor',[0.6 0.6 0.6]);
                obj.Handles.MarkersBeats = plot(obj.HeartBeats,zeros(size(obj.HeartBeats)),'d','Color',obj.Colors(3,:),'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.Axes.SubPeaks,'MarkerSize',12,'MarkerFaceColor',obj.Colors(3,:));
                obj.SubplotVisual;

                obj.Previous = obj.Parameters.Current;
                obj.Previous.File = obj.RawFile;
                
                if ~isempty(obj.HeartBeats)
                    obj.ProcessHeartRate;
                else
                    delete(obj.Axes.SubHR.Children)
                    obj.SubplotVisual;
                    obj.EnableAll;
                end
            else
                obj.EnableAll;
            end
        end


        function ProcessHeartRate(obj)
            % Make sure interactions are disabled during processing
            obj.DisableAll;

            % Use a slinding mean to obtain heart rate
            [TempHeartBeats,TempHeartRate] = SlidingMean(obj.HeartBeats,obj.Parameters.Current.SlidingWindowSize,'SharpBreaks',false);
            if ~isempty(obj.RemovedWindows)
                for R = 1 : size(obj.RemovedWindows,1)
                    RemoveIndx = TempHeartBeats>=obj.RemovedWindows(R,1) & TempHeartBeats <= (obj.RemovedWindows(R,2)+obj.Parameters.Current.SlidingWindowSize);
                    TempHeartRate(RemoveIndx) = NaN;
                end
            end

            if ~isempty(obj.Artefacts)
                for R = 1 : size(obj.Artefacts,1)
                    RemoveIndx = TempHeartBeats>=obj.Artefacts(R,1) & TempHeartBeats <= (obj.Artefacts(R,2)+obj.Parameters.Current.SlidingWindowSize);
                    TempHeartRate(RemoveIndx) = NaN;
                end
            end

            obj.HeartRate = [TempHeartBeats,TempHeartRate];

            hold(obj.Axes.SubHR,'on')
            delete(obj.Axes.SubHR.Children)
            if strcmpi(obj.Parameters.Current.Unit,'bpm')
                plot(obj.HeartRate(:,1),60*obj.HeartRate(:,2),'LineWidth',1,'Color',obj.Colors(2,:),'Parent',obj.Axes.SubHR)
                obj.Axes.SubHR.YLabel.String = 'Heart rate (bpm)';
                Factor = 60;
            else
                plot(obj.HeartRate(:,1),obj.HeartRate(:,2),'LineWidth',1,'Color',obj.Colors(2,:),'Parent',obj.Axes.SubHR)
                obj.Axes.SubHR.YLabel.String = 'Heart rate (Hz)';
                Factor = 1;
            end
            MaxT = Factor*max(obj.HeartRate(:,2));
            MinT = Factor*min(obj.HeartRate(:,2));
            Min = MinT - 0.05*(MaxT-MinT);
            Max = MaxT + 0.05*(MaxT-MinT);
            obj.Handles.Min.SubHR = Min;
            obj.Handles.Max.SubHR = Max;
            obj.Axes.SubHR.YLim = [Min Max];
            if ~isempty(obj.Artefacts)
                % Plot ranges discarded because of artefacts
                obj.Handles.FillArtefact.SubHR = arrayfun(@(x) fill(([obj.Artefacts(x,1) obj.Artefacts(x,2) obj.Artefacts(x,2) obj.Artefacts(x,1)]), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor','none','Parent',obj.Axes.SubHR),1:numel(obj.Artefacts(:,1)));
                uistack(obj.Handles.FillArtefact.SubHR,'bottom')
                obj.Handles.FillWindowArtefact.SubHR = arrayfun(@(x) fill([0 obj.Parameters.Current.SlidingWindowSize obj.Parameters.Current.SlidingWindowSize 0]+obj.Artefacts(x,2), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor',[0.75 0.75 0.75],'FaceColor','none','LineStyle','--','LineWidth',1,'Parent',obj.Axes.SubHR),1:size(obj.Artefacts,1));
                uistack(obj.Handles.FillWindowArtefact.SubHR,'bottom')
            end
            if ~isempty(obj.RemovedWindows)
                % Plot ranges discarded because of artefacts
                obj.Handles.FillRemovedWindows.SubHR = arrayfun(@(x) fill([obj.RemovedWindows(x,1) obj.RemovedWindows(x,2) obj.RemovedWindows(x,2) obj.RemovedWindows(x,1)], [Min Min Max Max],[0.85 0.85 0.9],'EdgeColor','none','Parent',obj.Axes.SubHR,'ButtonDownFcn',@(src,evt)obj.SelectWindow(src,evt),'Tag',num2str(x)),1:size(obj.RemovedWindows,1));
                uistack(obj.Handles.FillRemovedWindows.SubHR,'bottom')
                obj.Handles.FillWindowRemoved.SubHR = arrayfun(@(x) fill([0 obj.Parameters.Current.SlidingWindowSize obj.Parameters.Current.SlidingWindowSize 0]+obj.RemovedWindows(x,2), [Min Min Max Max],[0.75 0.75 0.75],'EdgeColor',[0.75 0.75 0.75],'FaceColor','none','LineStyle','--','LineWidth',1,'Parent',obj.Axes.SubHR),1:size(obj.RemovedWindows,1));
                uistack( obj.Handles.FillWindowRemoved.SubHR,'bottom')
            end
            obj.SubplotVisual;
            obj.EnableAll;
            drawnow
            obj.Figure.KeyPressFcn = {@(Src,Key)obj.KeyPressCB(Src,Key)};
        end


        function ProcessCB(obj)
            obj.DisableAll;
            % Divide the signal around long artefacts / empty ranges
            EmptyRanges = [];
            EmptyRangesIndex = (find(diff(obj.HeartBeats)>obj.Parameters.Current.Discontinue))';
            if ~isempty(EmptyRangesIndex)
                EmptyRanges = obj.GetContinuousRanges(EmptyRangesIndex);
                EmptyRanges = [EmptyRangesIndex(EmptyRanges(:,1)), EmptyRangesIndex(EmptyRanges(:,2))+1];
            end
            ToRemove = [obj.Artefacts;obj.RemovedWindows;obj.HeartBeats(EmptyRanges)];
            if ~isempty(ToRemove)
                [~,IndxSort] = sort(ToRemove(:,1));
                TempIndxRmv = ToRemove(IndxSort,:);
                % Merge potential overlaps
                for RR = 2 : size(TempIndxRmv,1)
                    if (TempIndxRmv(RR,1)<TempIndxRmv(RR-1,2))
                        TempIndxRmv(RR,1) = TempIndxRmv(RR-1,1);
                        TempIndxRmv(RR-1,1) = NaN;
                    end
                    if (TempIndxRmv(RR,2)<TempIndxRmv(RR-1,2))
                        TempIndxRmv(RR,2) = TempIndxRmv(RR-1,2);
                        TempIndxRmv(RR-1,2) = NaN;
                    end
                end
                TempIndxRmv = TempIndxRmv(~any(isnan(TempIndxRmv),2),:);
            else
                TempIndxRmv = [];
            end

            % Merge close ranges
            if ~isempty(TempIndxRmv)
                for KF = 2 : size(TempIndxRmv,1)
                    if (TempIndxRmv(KF,1)-TempIndxRmv(KF-1,2))<obj.Parameters.Current.Discontinue
                        TempIndxRmv(KF-1,2) = TempIndxRmv(KF,2);
                        TempIndxRmv(KF,1) = TempIndxRmv(KF-1,1);
                    end
                end
                TempIndxRmv = sort(unique(TempIndxRmv,'rows'));
                if ~isempty(TempIndxRmv)
                    % Deduce the ranges to process
                    GlobalRanges = [];
                    if TempIndxRmv(1)~=0
                        GlobalRanges = [0 TempIndxRmv(1)];
                    end
                    if size(TempIndxRmv,1)>1
                        for M = 1 : size(TempIndxRmv,1)-1   
                            GlobalRanges = [GlobalRanges; TempIndxRmv(M,2),TempIndxRmv(M+1,1)];
                        end
                    end
                    if TempIndxRmv(1)==1 && size(TempIndxRmv,1)==1
                        GlobalRanges = [TempIndxRmv(2) obj.Times(end)];
                    elseif TempIndxRmv(end,2) ~= obj.Times(end)
                        GlobalRanges = [GlobalRanges; TempIndxRmv(end,2),obj.Times(end)];
                    end
                else
                    GlobalRanges = [1 obj.Times(end)];
                end
            else
                GlobalRanges = [1 numel(obj.Preprocessed)];
            end

            % Call the main algorithm 
            obj.LastFailed = 0;
            Algo_HeartBeats = cell(numel(GlobalRanges(:,1)),1);
            [~,~,Indx] = intersect(round(obj.HeartBeats,6),round(obj.Peaks,6));
            AllShapes = obj.Shapes(Indx,:);

            for P = 1 : obj.Parameters.Current.PassNumber
                parfor G = 1 : numel(GlobalRanges(:,1))
                    % Retrieve the peaks for each range
                    RangeIndex = find(obj.HeartBeats>=GlobalRanges(G,1) & obj.HeartBeats<=GlobalRanges(G,2));
                    if ~isempty(RangeIndex)
                        % Forward
                        [~,Algo_HeartBeats{G},ShapesOut] = obj.Projection(obj.HeartBeats(RangeIndex),AllShapes(RangeIndex,:),GlobalRanges(G,2));

                        if ~isempty(Algo_HeartBeats{G})
                            % Backward
                            % Get initial shift
                            TimeStart = Algo_HeartBeats{G}(1);
                            % Get time intervals (add the range limit to
                            % transform it at the same time)
                            TimeIntervals = diff([GlobalRanges(G,1) Algo_HeartBeats{G}]);
                            % Flip time intervals and derive timestamps
                            Backward_Beats = [0 cumsum(fliplr(TimeIntervals))];
                            OriginalBackward_Last = Backward_Beats(end-1);
                            % Run Algorithm
                            [~,Backward_Beats,~] = obj.Projection(Backward_Beats(1:end-1),flipud(ShapesOut),Backward_Beats(end));
                            % Flip and shift result back
                            Algo_HeartBeats{G} = TimeStart + (OriginalBackward_Last - Backward_Beats(end)) + [0 cumsum(fliplr(diff(Backward_Beats)))];
                        end
                    end
                end
                Algo_HeartBeats(isempty(Algo_HeartBeats)) = [];
                % Round at a rather far decimal to account for
                % arithmetic precision issues
                obj.HeartBeats = round(cell2mat(Algo_HeartBeats'),6);
                obj.Peaks = round(obj.Peaks,6);
            end

            delete(obj.Handles.MarkersBeats)
            delete(obj.Handles.MarkersAll)
            obj.Handles.MarkersAll = plot(obj.Peaks,zeros(size(obj.Peaks)),'d','Color',[0.6 0.6 0.6],'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.Axes.SubPeaks,'MarkerSize',12,'MarkerFaceColor',[0.6 0.6 0.6]);
            obj.Handles.MarkersBeats = plot(obj.HeartBeats,zeros(size(obj.HeartBeats)),'d','Color',obj.Colors(3,:),'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.Axes.SubPeaks,'MarkerSize',12,'MarkerFaceColor',obj.Colors(3,:));
            if obj.Handles.EnableShapes.Value==1
                delete(obj.Handles.ShapesBeats);
                obj.Parameters.Current.ShapesEnable = 1;

                % Instead of plotting individual waveforms, we'll just
                % overlay full ECG traces again, with NaN ranges
                % (much faster/efficient even when navigating
                % afterwards)
                Indx = obj.Intersect(obj.HeartBeats,obj.Peaks);
                [~,Indx2] = setdiff(obj.Peaks,obj.HeartBeats);
                TempSignal1 = NaN(size(obj.Preprocessed));
                TempSignal2 = NaN(size(obj.Preprocessed));
                FullIndx1 = obj.RangeShapes(Indx,:);
                FullIndx1 = sort(FullIndx1(:));
                FullIndx2 = obj.RangeShapes(Indx2,:);
                FullIndx2 = sort(FullIndx2(:));
                TempSignal1(FullIndx1) = obj.Preprocessed(FullIndx1);
                TempSignal2(FullIndx2) = obj.Preprocessed(FullIndx2);
                obj.Handles.ShapesBeats = [plot(obj.Times, TempSignal2,'Color',[0.8 0.8 0.8],'LineWidth',1.5,'Parent',obj.Axes.SubPeaks);
                    plot(obj.Times, TempSignal1,'Color',obj.Colors(2,:),'LineWidth',1.5,'Parent',obj.Axes.SubPeaks)];

                delete(obj.Handles.MarkersBeats)
                delete(obj.Handles.MarkersAll)
                obj.Handles.MarkersAll = plot(obj.Peaks,zeros(size(obj.Peaks)),'d','Color',[0.6 0.6 0.6],'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.Axes.SubPeaks,'MarkerSize',12,'MarkerFaceColor',[0.6 0.6 0.6]);
                obj.Handles.MarkersBeats = plot(obj.HeartBeats,zeros(size(obj.HeartBeats)),'d','Color',obj.Colors(3,:),'MarkerEdgeColor','k','ButtonDownFcn',@(~,~)obj.SelectBeat,'Parent',obj.Axes.SubPeaks,'MarkerSize',12,'MarkerFaceColor',obj.Colors(3,:));
            else
                obj.Handles.ShapesBeats = [];
            end
            if obj.Parameters.Current.BeatPeaksEnable
                Indx = obj.Intersect(obj.HeartBeats,obj.Peaks);
                delete(obj.Handles.BeatPeaks)                    
                obj.Handles.BeatPeaks = plot((obj.BeatPeaks(Indx,1))', (obj.BeatPeaks(Indx,2))','o','Color','k','MarkerSize',10,'LineWidth',1.5,'Parent',obj.Axes.SubPeaks);
            else
                obj.Handles.BeatPeaks = [];
            end
            if ~isempty(obj.HeartBeats)
                obj.ProcessHeartRate;
            else
                delete(obj.Axes.SubHR.Children)
                obj.SubplotVisual;
                obj.EnableAll;
            end
        end

        function [ScoreG,HeartBeats,Shapes] = Projection(obj,HeartBeats,Shapes,EndBoundaries,varargin)
            % The idea is for the function to be called recursively if
            % needed, to compare how the choice of one potential peak vs
            % another would influence the analysis further, and therefore
            % make a better choice (via a global "score" for each of the
            % different possibilities)
            ScoreG = NaN;
            Abort = false;
            if isempty(varargin)
                IterNum = 1;
                % Define suspicious intervals
                SuspiciousRangeHigh = 1 / obj.Parameters.Current.SuspiciousFrequencyHigh;
                SuspiciousRangeLow = 1 / obj.Parameters.Current.SuspiciousFrequencyLow;
                % Find suspicious ranges
                IndexInvestigationAll = find(diff(HeartBeats)<SuspiciousRangeHigh | diff(HeartBeats)>SuspiciousRangeLow );
                if ~isempty(IndexInvestigationAll)
                    Ranges_Investigated = obj.GetContinuousRanges(IndexInvestigationAll);
                    % Convert to absolute time (Heartbeats index will change)
                    Ranges_Investigated_Times = HeartBeats(IndexInvestigationAll(Ranges_Investigated(:,[1 2])));
                else
                    Abort = true;
                end
            else
                IterNum = varargin{1};
                if IterNum > 3
                    return % Stop the subiteration and force the calling iteration to compute a score and choose
                else
                    IterNum = IterNum + 1;
                end
                % Assessment mode
                if isempty(HeartBeats)
                    return
                end
                Ranges_Investigated_Times = HeartBeats([1 end]);
                IndexStart = 5;
            end

            if ~Abort
                if isempty(varargin)
                    % Ranges to find a starting point
                    % (good intervals stability and correlation values)
                    CorrSegmentValues = arrayfun(@(x) max(xcorr(zscore(Shapes(x,:)),obj.Template))/obj.MaxCorr,1:numel(HeartBeats));
                    CorrAdm = find(CorrSegmentValues>=0.7); % Threshold could be adjusted if needed
                    CorrRanges = obj.GetContinuousRanges(CorrAdm);
                    CorrRanges_Limited = CorrRanges(CorrRanges(:,3)>=4,1:2); % At least 4 consecutive values satisfying the criterion
                    % To full index
                    Corr_Limited_Index = false(size(HeartBeats));
                    for Int = 1 : length(CorrRanges_Limited(:,1))
                        Corr_Limited_Index(CorrAdm(CorrRanges_Limited(Int,1)):CorrAdm(CorrRanges_Limited(Int,2))) = true;
                    end
                    % Intervals
                    Intervals = diff(HeartBeats);
                    Intervals_Limited = find(Intervals<SuspiciousRangeLow | Intervals>SuspiciousRangeHigh);
                    % To full index
                    Intervals_Limited_Index = false(size(HeartBeats));
                    for Int = 1 : length(Intervals_Limited)
                        Intervals_Limited_Index(Intervals_Limited(Int):Intervals_Limited(Int)+1) = true;
                    end
                    % Intervals stability
                    Intervals_Stable = diff(Intervals);
                    Intervals_Stable_Indx = find(abs(Intervals_Stable)<=obj.Parameters.Current.StableIndex*obj.Frequency/1000);
                    Intervals_Stable_Range = obj.GetContinuousRanges(Intervals_Stable_Indx);
                    Intervals_Stable_Range = Intervals_Stable_Range(Intervals_Stable_Range(:,3)>=3,1:2);
                    Intervals_Stable_Range = [Intervals_Stable_Range(:,1),Intervals_Stable_Range(:,2)+2]; % Convert to real indexes (from double diff)
                    % Range to index
                    Intervals_Stable_Range_Index = false(size(HeartBeats));
                    for Int = 1 : length(Intervals_Stable_Range(:,1))
                        Intervals_Stable_Range_Index(Intervals_Stable_Range(Int,1):Intervals_Stable_Range(Int,2)) = true;
                    end
                    % Apply the different logical indexings
                    SuitedIndex = Corr_Limited_Index & Intervals_Limited_Index & Intervals_Stable_Range_Index;
                    SuitedValues = HeartBeats(SuitedIndex);

                    % If this does not give us a suitable value AT ALL, we can
                    % lower our standards
                    % (even if the "good" range is very far, it means it can be
                    % used in the reverse direction afterwards: that's OK)
                    if isempty(SuitedValues)
                        CorrSegmentValues = arrayfun(@(x) max(xcorr(zscore(Shapes(x,:)),obj.Template))/obj.MaxCorr,1:numel(HeartBeats));
                        CorrAdm = find(CorrSegmentValues>=0.5); % Threshold could be adjusted if needed
                        CorrRanges = obj.GetContinuousRanges(CorrAdm);
                        CorrRanges_Limited = CorrRanges(CorrRanges(:,3)>=4,1:2); % At least 4 consecutive values satisfying the criterion
                        % To full index
                        Corr_Limited_Index = false(size(HeartBeats));
                        for Int = 1 : length(CorrRanges_Limited(:,1))
                            Corr_Limited_Index(CorrAdm(CorrRanges_Limited(Int,1)):CorrAdm(CorrRanges_Limited(Int,2))) = true;
                        end
                        % Intervals
                        Intervals = diff(HeartBeats);
                        Intervals_Limited = find(Intervals>SuspiciousRangeLow & Intervals<1.2*SuspiciousRangeHigh); % Decreased
                        % To full index
                        Intervals_Limited_Index = false(size(HeartBeats));
                        for Int = 1 : length(Intervals_Limited)
                            Intervals_Limited_Index(Intervals_Limited(Int):Intervals_Limited(Int)+1) = true;
                        end
                        % Intervals stability
                        Intervals_Stable = diff(Intervals);
                        Intervals_Stable_Indx = find(abs(Intervals_Stable)<=0.6 * obj.Parameters.Current.StableIndex*obj.Frequency/1000); % Decreased
                        Intervals_Stable_Range = obj.GetContinuousRanges(Intervals_Stable_Indx);
                        Intervals_Stable_Range = Intervals_Stable_Range(Intervals_Stable_Range(:,3)>=3,1:2);
                        Intervals_Stable_Range = [Intervals_Stable_Range(:,1),Intervals_Stable_Range(:,2)+2]; % Convert to real indexes (from double diff)
                        % Range to index
                        Intervals_Stable_Range_Index = false(size(HeartBeats));
                        for Int = 1 : length(Intervals_Stable_Range(:,1))
                            Intervals_Stable_Range_Index(Intervals_Stable_Range(Int,1):Intervals_Stable_Range(Int,2)) = true;
                        end
                        % Apply the different logical indexings
                        SuitedIndex = Corr_Limited_Index & Intervals_Limited_Index & Intervals_Stable_Range_Index;
                        SuitedValues = HeartBeats(SuitedIndex);
                    end

                    if isempty(SuitedValues)
                        return
                    end
                end

                % Loop through the ranges to correct
                for G = 1 : size(Ranges_Investigated_Times,1)
                    if isempty(varargin)
                        % To initialize the segment, find a preceeding stable range
                        % First, get the updated index
                        IndexStart = find(HeartBeats == Ranges_Investigated_Times(G,1));
                        % In case it's at the very beginning, ignore
                        % (processed during second pass)
                        if IndexStart<=4
                            Break = true;
                        else
                            Break = false;
                        end
                    else
                        IndexStart = 5;
                        Break = false;
                    end
                    if ~Break
                        BreakLoop = false;
                        % Ideally the beats just before, but otherwise we look
                        % further
                        if isempty(varargin) && ~all(SuitedIndex(IndexStart-3:IndexStart))
                            InvestigatedPeak = find(HeartBeats<Ranges_Investigated_Times(G,1) & HeartBeats>obj.LastFailed & SuitedIndex,1,'last');
                             if isempty(InvestigatedPeak)
                                 BreakLoop = true;
                                 obj.LastFailed = Ranges_Investigated_Times(G,1);
                             end
                        else
                            InvestigatedPeak = IndexStart-1;
                        end
                        if isempty(InvestigatedPeak)
                            BreakLoop = true;
                        end
                        % Loop until the segment is processed or it fails
                        while ~BreakLoop && ~isempty(InvestigatedPeak) && InvestigatedPeak<= numel(HeartBeats) && HeartBeats(InvestigatedPeak)<=Ranges_Investigated_Times(G,2)
                            % We use the previous intervals as reference as a first
                            % approach
                            HeartBeatsSamples = HeartBeats * obj.Frequency;
                            Before = (diff(HeartBeatsSamples(InvestigatedPeak-3:InvestigatedPeak)))';
                            Combinations = combnk(1:3,2);
                            Intervals = abs(diff(Before(Combinations),1,2));
                            if numel(Intervals(Intervals>=obj.Parameters.Current.Outlier*obj.Frequency/1000))>1
                                Before = Before(Combinations(Intervals<obj.Parameters.Current.Outlier*obj.Frequency/1000,:));
                            end
                            if isempty(Before)
                                % Can happen (rarely) when bradycardia interferes too much with the thresh
                                Before = 4*obj.Parameters.Current.Outlier*obj.Frequency/1000;
                            end
                            RangeBefore = round(mean(Before));
                            xNorm = -RangeBefore/2:RangeBefore/2;
                            Norm = normpdf(xNorm,0,RangeBefore/5);
                            Norm = Norm/max(Norm);

                            % Find peaks in a window just after the last peak
                            IndexInvestigated = find(HeartBeatsSamples(InvestigatedPeak:end)>(HeartBeatsSamples(InvestigatedPeak)+1.4*RangeBefore),1,'first');
                            IndexInvestigated = InvestigatedPeak+1:(InvestigatedPeak+IndexInvestigated-1);
                            if isempty(IndexInvestigated)
                                % Allow for some extension of the window
                                IndexInvestigated = find(HeartBeatsSamples(InvestigatedPeak:end)>HeartBeatsSamples(InvestigatedPeak)+1.8*RangeBefore,1,'first');
                                IndexInvestigated = InvestigatedPeak+1:(InvestigatedPeak+IndexInvestigated-1);
                            end

                            % If we have more than one peak, we have to choose
                            if numel(IndexInvestigated)>1
                                % Compute scores for each of the peaks
                                Investigated = HeartBeatsSamples(IndexInvestigated);
                                CorrScore = zeros(numel(Investigated),1);
                                PositionScore = zeros(numel(Investigated),1);
                                TotalScore = zeros(numel(Investigated),1);
                                for IP = 1 : numel(IndexInvestigated)
                                    Score = Norm(find(xNorm >= HeartBeatsSamples(IndexInvestigated(IP))-HeartBeatsSamples(InvestigatedPeak)-RangeBefore,1,'first'));
                                    if ~isempty(Score)
                                        PositionScore(IP) = Score;
                                    else
                                        PositionScore(IP) = 0.1;
                                    end
                                    CorrScore(IP) = max(xcorr(zscore(Shapes(IndexInvestigated(IP),:)),obj.Template))/obj.MaxCorr;
                                    TotalScore(IP) = PositionScore(IP)*CorrScore(IP);
                                end

                                % If we have a very good candidate, we keep it
                                if any(TotalScore>=0.6)
                                    [~,BestIndex] = max(TotalScore);
                                    % We remove the peaks BEFORE the best
                                    if BestIndex ~= 1
                                        DeleteIndex = 1:BestIndex-1;
                                        HeartBeats(IndexInvestigated(DeleteIndex)) = [];
                                        Shapes(IndexInvestigated(DeleteIndex),:) = [];
                                        if isempty(varargin)
                                            SuitedIndex(IndexInvestigated(DeleteIndex)) = [];
                                        end
                                    else
                                        DeleteIndex = [];
                                        if isempty(varargin)
                                            SuitedIndex(IndexInvestigated(1)) = 1;
                                        end
                                    end
                                    % We set the new peak for the loop
                                    InvestigatedPeak = IndexInvestigated(BestIndex-numel(DeleteIndex));
                                else
                                    % We try to extend a bit to make
                                    % sure we don't miss bradycardia
                                    IndexInvestigated = InvestigatedPeak+1:InvestigatedPeak+find(HeartBeatsSamples(InvestigatedPeak:end)>HeartBeatsSamples(InvestigatedPeak)+1.8*RangeBefore,1,'first');
                                    ToTest = IndexInvestigated;
                                    % We have to try the different possibilities
                                    % and see what's the best
                                    if isempty(ToTest)
                                        BreakLoop = true;
                                    else
                                        ScoreAll = NaN(size(ToTest));
                                        for T = 1 : numel(ToTest)
                                            IndexEnd = find(HeartBeats>(HeartBeats(InvestigatedPeak)+5*1/obj.Parameters.Current.SuspiciousFrequencyLow),1,'first');
                                            % We don't want the other preceeding candidates to be included
                                            HeartBeatsT = HeartBeats([InvestigatedPeak-3:InvestigatedPeak ToTest(T):IndexEnd]);
                                            ShapesT = Shapes([InvestigatedPeak-3:InvestigatedPeak ToTest(T):IndexEnd],:);
                                            [ScoreAll(T),~,~] = obj.Projection(HeartBeatsT,ShapesT,EndBoundaries,IterNum);
                                        end

                                        BestIndex = find(ScoreAll>0.7,1,'first');
                                        % We remove the peaks BEFORE the best
                                        if BestIndex ~= 1
                                            DeleteIndex = 1:BestIndex-1;
                                            HeartBeats(ToTest(DeleteIndex)) = [];
                                            Shapes(ToTest(DeleteIndex),:) = [];
                                            if isempty(varargin)
                                                SuitedIndex(ToTest(DeleteIndex)) = [];
                                            end
                                        else
                                            DeleteIndex = [];
                                            if isempty(varargin)
                                                SuitedIndex(ToTest(1)) = 1;
                                            end
                                        end
                                        % We set the new peak for the loop
                                        InvestigatedPeak = IndexInvestigated(BestIndex-numel(DeleteIndex));
                                    end
                                end
                                if ~isempty(varargin)
                                    % Compute the score
                                    HeartBeatsSamples = HeartBeats * obj.Frequency;
                                    Before = (diff(HeartBeatsSamples(1:4)))';
                                    Combinations = combnk(1:3,2);
                                    Intervals = abs(diff(Before(Combinations),1,2));
                                    if numel(Intervals(Intervals>=obj.Parameters.Current.Outlier*obj.Frequency/1000))>1
                                        Before = Before(Combinations(Intervals<obj.Parameters.Current.Outlier*obj.Frequency/1000,:));
                                    end
                                    if isempty(Before)
                                        % Can happen (rarely) when bradycardia interferes too much with the thresh
                                        Before = 4*obj.Parameters.Current.Outlier*obj.Frequency/1000;
                                    end
                                    RangeBefore = round(mean(Before));
                                    xNorm = -RangeBefore:RangeBefore;
                                    Norm = normpdf(xNorm,0,RangeBefore/3);
                                    Norm = Norm/max(Norm);
                                    PositionScore = zeros(1,numel(HeartBeatsSamples)-3);
                                    for IP = 4 : numel(HeartBeatsSamples)
                                        PScore = Norm(find(xNorm >= HeartBeatsSamples(IP)-HeartBeatsSamples(IP-1)-RangeBefore,1,'first'));
                                        if ~isempty(PScore)
                                            PositionScore(IP-3) = PScore;
                                        else
                                            PositionScore(IP-3) = 0.1;
                                        end
                                    end
                                    CorrScore = arrayfun(@(x) max(xcorr(zscore(Shapes(x,:)),obj.Template))/obj.MaxCorr, 4:numel(HeartBeatsSamples));
                                    ScoreG = mean(CorrScore .* PositionScore);
                                end
                            else
                                if ~isempty(varargin)
                                    % Compute the score
                                    HeartBeatsSamples = HeartBeats * obj.Frequency;
                                    Before = (diff(HeartBeatsSamples(1:4)))';
                                    Combinations = combnk(1:3,2);
                                    Intervals = abs(diff(Before(Combinations),1,2));
                                    if numel(Intervals(Intervals>=obj.Parameters.Current.Outlier*obj.Frequency/1000))>1
                                        Before = Before(Combinations(Intervals<obj.Parameters.Current.Outlier*obj.Frequency/1000,:));
                                    end
                                    if isempty(Before)
                                        % Can happen (rarely) when bradycardia interferes too much with the thresh
                                        Before = 4*obj.Parameters.Current.Outlier*obj.Frequency/1000;
                                    end
                                    RangeBefore = round(mean(Before));
                                    xNorm = -RangeBefore:RangeBefore;
                                    Norm = normpdf(xNorm,0,RangeBefore/3);
                                    Norm = Norm/max(Norm);
                                    PositionScore = zeros(1,numel(HeartBeatsSamples)-3);
                                    for IP = 4 : numel(HeartBeatsSamples)
                                        PScore = Norm(find(xNorm >= HeartBeatsSamples(IP)-HeartBeatsSamples(IP-1)-RangeBefore,1,'first'));
                                        if ~isempty(PScore)
                                            PositionScore(IP-3) = PScore;
                                        else
                                            PositionScore(IP-3) = 0.1;
                                        end
                                    end
                                    CorrScore = arrayfun(@(x) max(xcorr(zscore(Shapes(x,:)),obj.Template))/obj.MaxCorr, 4:numel(HeartBeatsSamples));
                                    ScoreG = mean(CorrScore .* PositionScore);
                                else
                                    if (EndBoundaries-HeartBeats(InvestigatedPeak)) < obj.Parameters.Current.Discontinue
                                        HeartBeats(InvestigatedPeak+1:end) = [];
                                        Shapes(InvestigatedPeak+1:end,:) = [];
                                    end
                                    BreakLoop = true;
                                end
                                InvestigatedPeak = InvestigatedPeak + 1;
                            end
                        end
                    end
                end
            end
        end
    end

    methods(Static)
        function RangeInfo = GetContinuousRanges(IndexIn)
            Thresh = 1;
            IndexDiff = find((diff(IndexIn)) > Thresh);
            if isempty(IndexDiff)
                RangeInfo = [1 numel(IndexIn) numel(IndexIn)];
            elseif numel(IndexDiff) == 1
                RangeInfo = [1, IndexDiff, IndexDiff;...
                    IndexDiff + 1, numel(IndexIn), numel(IndexIn) - IndexDiff];
            else
                RangeInfo = zeros(numel(IndexDiff)+1,3);
                RangeInfo(1,:) = [1, IndexDiff(1), IndexDiff(1)];

                for K = 1 : numel(IndexDiff)-1
                    RangeInfo(K+1,:) = [IndexDiff(K)+1, IndexDiff(K+1), IndexDiff(K+1) - IndexDiff(K)];
                end
                RangeInfo(end,:) = [IndexDiff(end)+1,numel(IndexIn), numel(IndexIn) - IndexDiff(end)];
            end
        end
        function Vector = InterpNaN(Vector,MaxRange)
            Indices = 1 : numel(Vector);
            NaNIndex = isnan(Vector);
            % Check that we don't have large ranges - otherwise raise an
            % error
            RangesInfo = FindContinuousRange(find(NaNIndex));
            if any(RangesInfo(:,3)>MaxRange)
                warndlg(['Some NaN ranges exceed the defined length that' ...
                    ' was defined as ''safe''. Make sure the resulting' ...
                    ' signal is valid.'],'WARNING')
            end
            Vector(NaNIndex) = interp1(Indices(~NaNIndex), Vector(~NaNIndex), Indices(NaNIndex), 'linear');

        end
        function isEqual = Intersect(ArrayA,ArrayB)
            if ~(isvector(ArrayA) && isvector(ArrayB))
                error('Arrays must be vectors.')
            end
            if size(ArrayA,1)~=size(ArrayB,1)
                ArrayA = ArrayA';
            end
             [~,~,isEqual] = intersect(round(ArrayA,6),round(ArrayB,6));
        end
        function  DC = DefColors
            DC = [0.00,0.45,0.74;
                0.85,0.33,0.10;
                0.93,0.69,0.13;
                0.49,0.18,0.56;
                0.47,0.67,0.19;
                0.30,0.75,0.93;
                0.64,0.08,0.18];
        end
    end
end
