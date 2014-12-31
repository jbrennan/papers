//-----------------
// Content Editable
//-----------------

function focussedEditable(event) {
	
	
	// Select the text after a delay, because Javascript.
	var element = event.currentTarget;
	requestAnimationFrame(function() {
		selectElementContents(element);
	});
}


function blurredEditable(event) {
	
	var property = event.currentTarget.getAttribute("data-property");
	var value = event.currentTarget.textContent;
	
	var data = {
		apisecret: APISecret,
		documentID: documentID,
		property: property,
		value: value
	};
	
	$.ajax({
		
		type: "POST",
		url: "/api/v1/updatekey",
		contentType: 'application/json',
		data: JSON.stringify(data),
		success: function(r) {
			if (r.status == "OK") {
				
			} else {
				console.log(r.error)
			}
		}
		
		
	});
}


function keyDownOnEditable(event) {
	var enterKeyCode = 13;
	if (event.keyCode == enterKeyCode) {
		event.currentTarget.blur();
		event.preventDefault();
	}
}

// from: http://stackoverflow.com/a/6150060/106658
function selectElementContents(el) {
	var range = document.createRange();
	range.selectNodeContents(el);
	var sel = window.getSelection();
	sel.removeAllRanges();
	sel.addRange(range);
}
