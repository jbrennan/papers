//---------------
// Drag & drop uploading
//---------------

document.documentElement.ondragover = function() {
	this.className = 'hover';
	return false;
};


document.documentElement.ondragend = function() {
	this.className = '';
	return false;
};



document.documentElement.ondrop = function(event) {
	event.preventDefault && event.preventDefault();
	this.className = '';
	
	var files = event.dataTransfer.files;
	uploadFiles(files);
	
	
	return false;
};


function uploadFiles(files) {
	var formData = new FormData();
	var uploadingCount = 0;
	
	for (var i = 0; i < files.length; i++) {
		
		var file = files[i];
		
		if (file.type !== "application/pdf") {
			continue;
		}
		var name = file.name;
		if (name === undefined) {
			name = "untitled file";
		}
		
		formData.append(name, file)
		uploadingCount++;
	}
	
	if (uploadingCount < 1) {
		return;
	}
	var request = new XMLHttpRequest();
	request.open("POST", "/api/v1/document/upload");
	request.onload = function() {
		if (request.status === 200) {
			location.reload();
		} else {
			console.log("error uploading the file...");
		}
	}
	
	request.send(formData);
}