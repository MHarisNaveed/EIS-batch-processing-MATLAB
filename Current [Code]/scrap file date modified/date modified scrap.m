% Set root directory
rootFolder = pwd; 
allFiles = dir(fullfile(rootFolder, '**', '*.*'));

% Remove directories and filter system/hidden files
allFiles = allFiles(~[allFiles.isdir]);
allFiles = allFiles(~startsWith({allFiles.name}, '.')); 

% Preallocate
numFiles = length(allFiles);
fileNames = cell(numFiles, 1);
folderPaths = cell(numFiles, 1);
datesMod = datetime(zeros(numFiles, 1), 'ConvertFrom', 'datenum');
fileFormats = cell(numFiles, 1);
% FIX: Preallocate as an empty datetime array of the correct size
datesCreated = NaT(numFiles, 1); 

% Extract info
for i = 1:numFiles
    fileNames{i} = allFiles(i).name;
    folderPaths{i} = strrep(allFiles(i).folder, rootFolder, '.');
    datesMod(i) = datetime(allFiles(i).datenum, 'ConvertFrom', 'datenum');
    
    [~, ~, ext] = fileparts(allFiles(i).name);
    fileFormats{i} = ext;
    
    % Java-based Creation Date
    jFile = java.io.File(fullfile(allFiles(i).folder, allFiles(i).name));
    try
        attr = java.nio.file.Files.readAttributes(jFile.toPath(), 'basic', java.nio.file.LinkOption.NOFOLLOW_LINKS);
        % Convert Java file time to MATLAB datetime
        millis = attr.creationTime().toMillis();
        datesCreated(i) = datetime(millis/1000, 'ConvertFrom', 'posixtime', 'TimeZone', 'local');
    catch
        datesCreated(i) = datesMod(i); 
    end
end

% Create the table
T = table(fileNames, fileFormats, folderPaths, datesCreated, datesMod, ...
    'VariableNames', {'FileName', 'FileFormat', 'FolderPath', 'CreatedDate', 'DateModified'});

% SORTING
T = sortrows(T, {'FolderPath', 'CreatedDate'});

% DUPLICATE CHECK
[~, idx] = unique(T.FileName);
duplicateMask = true(height(T), 1);
duplicateMask(idx) = false;
T.IsDuplicateName = duplicateMask;

disp('--- Project File Hierarchy ---');
disp(T(1:min(10, height(T)), :));
writetable(T, 'Project_Full_Report.csv');
fprintf('Report saved as Project_Full_Report.csv\n');